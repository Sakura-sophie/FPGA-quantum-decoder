library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity my_FPGA is
    generic(
        img_width : integer := 12; -- In pixels
        img_height : integer := 12;
        atom_spacing : integer := 3; -- In pixels. Calibrate and alter this parameter from experiment.
        grid_size : integer :=3; -- 8x8
        roi_size : integer :=2; -- Region of interest in pixels surrounding atom sites. Will probs want to be greater in experiment. Eg 4x4.
        start_offset_x : integer :=2;
        start_offset_y : integer :=2; -- In pixels. Start of wherever you expect your atoms to fall in. 1st ROI.
        hist_data_l : std_logic_vector(13 downto 0) := "00000001001100"; -- Decimal 76
        hist_data_h : std_logic_vector(13 downto 0) := "00000001010100";  -- Decimal 84
        output_del : integer := 10000
    );
    port (
        clk : in  std_logic;
        reset : in  std_logic;
        img_bit_stream : in  std_logic_vector(13 downto 0);
        valid : in std_logic; -- signal given by camera each time theres information
        readout : out std_logic;
        Trigger : in std_logic;
        Q_1,Q_2,Q_3,Q_4: out std_logic;
        dac_dda : out signed(13 downto 0);
        IQWRT : out std_logic;
        IQSEL : out std_logic;
        IQCLK : out std_logic;
        IQRESET : out std_logic
    );
end entity my_FPGA;

architecture quantum_decoder of my_FPGA is

    type state_type is (FINDING_1, CONSTRUCT_TARGET, REARRANGE,SEARCH_DONOR, EXECUTE_MOVES,DELAY);
    signal STATE : state_type := FINDING_1;
    signal img_data_latched : std_logic_vector(13 downto 0) := (others => '0');
    signal start_read : std_logic :='0';
    signal count : unsigned(7 downto 0) := (others => '0'); --basically column
    signal row : unsigned(7 downto 0) := (others => '0');
    signal is_inside_roi : std_logic := '0';
    signal roi_first_pixel : std_logic := '0';
    signal roi_last_pixel  : std_logic := '0';
    signal site_col: integer range 0 to grid_size-1 := 0;
    signal site_row : integer range 0 to grid_size-1 := 0;
    signal flag : std_logic := '0';
    signal grid_val : std_logic := '0';

    type col_accum_array is array (0 to grid_size-1) of std_logic;

    type roi_status_array is array (0 to grid_size-1) of std_logic_vector(grid_size-1 downto 0);
    signal roi_results : roi_status_array := (others=>(others=>'0'));

    type grid_dxd_type is array (0 to grid_size-1) of std_logic_vector(grid_size-1 downto 0);
    signal target_grid : grid_dxd_type := (others => (others => '0'));
    signal target_r, target_c : integer range 0 to 7 := 0;

    signal x_addr_s : signed(7 downto 0);
    type move_cmd is record
        x_co   : std_logic_vector(7 downto 0);
        y_co   : std_logic_vector(7 downto 0);
        x_move_v : signed(7 downto 0);
        y_move_v : signed(7 downto 0);
    end record;
    type fifo_array is array (0 to 63) of move_cmd;

    signal fifo_storage : fifo_array;
    signal fifo_count   : integer range 0 to 64 := 0;-- alter for diff grid sizes
    signal i : integer := 0;
    signal readout_s : std_logic :='0';
    signal toggle : std_logic := '0';
    signal delay_s : integer range 0 to 100_000_000 := 0;
    signal phase : std_logic := '0';

    signal dac_signal_14bit : signed(13 downto 0);
    type dac_state_t is (SEL_SETUP, DATA_SETUP, WRT_HI, CLK_HI, BOTH_LO, SWAP_CHAN);
    signal dac_state : dac_state_t := SEL_SETUP;
    signal dac_timer : integer range 0 to 25 := 0;
    signal dac_sel   : std_logic := '1';
    constant DAC_DWELL : integer := 25;
    signal qs_1, qs_2, qs_3,qs_4 : std_logic :='0';
    signal clock_count : integer range 0 to 10000 := 0;
    signal clk_en : std_logic := '0';
    signal valid_1: std_logic;
    signal valid_2: std_logic;
    signal valid_phase: std_logic;
    signal wr_addr : integer range 0 to (img_height*img_width);
    type BRAM_buffer is array (0 to(img_height*img_width)) of std_logic_vector(13 downto 0);
    signal img_buffer : BRAM_buffer;
    signal frame_rdy : std_logic;
    signal rd_addr : integer range 0 to (img_height*img_width);
    signal img_data_latched_1 : std_logic_vector(13 downto 0) := (others => '0');
begin


    clk_en_gen: process(clk, reset)
    begin
    if reset = '0' then
        clock_count <= 0;
        clk_en <= '0';
    elsif rising_edge(clk) then
        if clock_count = 9999 then
            clock_count <= 0;
            clk_en <= '1';
        else
            clock_count <= clock_count + 1;
            clk_en <= '0';
        end if;
    end if;
    end process;
    
    valid_process: process(clk,reset)
    begin
    if reset = '0' then
        valid_1<='0';
        valid_2<='0';
        valid_phase<='0';
    elsif rising_edge(clk) then
        valid_1<=valid;
        valid_2<=valid_1;
        valid_phase<= valid_1 and not valid_2;
    end if;
    end process;
	
    BRAM_write: process(clk,reset)
    begin
    if reset ='0' then
    wr_addr<=0;
    img_buffer <= (others=>(others=>'0'));
    frame_rdy <= '0';
    elsif rising_edge(clk) then
        if valid_phase ='1' then
            img_buffer(wr_addr)<=img_bit_stream;
            wr_addr<= wr_addr+1;
        elsif wr_addr = (img_width*img_height - 1) then
                wr_addr   <= 0;
                frame_rdy <= '1';
       end if;                  
    end if;
    end process;
    
    BRAM_read:process(clk,reset)
    begin
    if reset = '0' then
        rd_addr <= 0;
        start_read<='0';
        img_data_latched <= (others =>'0');
        img_data_latched_1 <= (others =>'0');
        
    elsif rising_edge(clk)then
        if clk_en ='1' then
            if frame_rdy = '1' then
                start_read<='1';
                img_data_latched <=img_buffer(rd_addr);
                img_data_latched_1 <=img_data_latched;
                rd_addr<=rd_addr+1;
            elsif frame_rdy ='1' and rd_addr = (img_width*img_height - 1) then
                rd_addr <= 0;
            end if;
        end if;
    end if;
    end process;
   

    roi_process : process(count,row)
        variable x_rem, y_rem : integer;
        variable x_cur, y_cur : integer;
    begin
    is_inside_roi   <= '0';
    roi_first_pixel <= '0';
    roi_last_pixel  <= '0';
   	x_cur := to_integer(count) - start_offset_x;
    y_cur := to_integer(row) - start_offset_y;
    if (x_cur >=0) and (y_cur>=0) and (x_cur < grid_size*atom_spacing) and (y_cur < grid_size*atom_spacing) then
        x_rem := x_cur rem atom_spacing;
        y_rem := y_cur rem atom_spacing;

        if x_rem < roi_size and y_rem < roi_size then
            is_inside_roi<= '1';
            site_col <= x_cur / atom_spacing;
            site_row <= y_cur / atom_spacing;
            if x_rem = 0 and y_rem = 0 then
              	roi_first_pixel <= '1';
            end if;
            if x_rem = roi_size - 1 and y_rem = roi_size - 1 then
                roi_last_pixel <= '1';
            end if;
        else
            is_inside_roi<= '0';
        end if;
    end if;
    end process roi_process;


    finding_ones : process(clk, reset)
        variable current_bv : unsigned(13 downto 0);
        variable atom_counter : unsigned(7 downto 0) := TO_UNSIGNED(0,8);
        variable site_atom_hit : col_accum_array ;
        variable site_flag_hit : col_accum_array ;
        variable px_atom_hit : std_logic;
        variable px_flag_hit : std_logic;
        variable var_results : roi_status_array := (others=>(others=>'0'));
        variable found_empty : boolean := false;
        variable var_fifo : fifo_array;
        variable index : integer;

        begin
        if reset = '0' then
            qs_1<='0';
            qs_2<='0';
            qs_3 <='0';
            qs_4 <='0';

            count    <= (others => '0');
            row      <= (others => '0');
            site_atom_hit := (others=>'0');
            site_flag_hit := (others=>'0');
            STATE    <= FINDING_1;
            atom_counter := (others =>'0');
           	grid_val <= '0';
           	flag <= '0';
            roi_results <= (others=>(others=>'0'));
            var_results := (others=>(others=>'0'));
            index := 0;
            var_fifo := (others => (
                x_co   => (others => '0'),
                y_co   => (others => '0'),
                x_move_v => (others => '0'),
                y_move_v => (others => '0')
            ));
            fifo_count  <= 0;
            i <= 0;
            readout_s <='0';
            x_addr_s <= (others => '0');
            delay_s <= 0;

 	       elsif rising_edge(clk) then
 	          if clk_en='1' then
                case STATE is
                    when FINDING_1 =>
                        if start_read = '1' then
                            count <= count + 1;
                            current_bv := unsigned(img_data_latched_1);

                            if is_inside_roi= '1' then
                                px_atom_hit := '0';
                                px_flag_hit := '0';

                                if current_bv > unsigned(hist_data_h) then
                                    px_atom_hit := '1';
                                    px_flag_hit := '0';

                                elsif current_bv > unsigned(hist_data_l) then
                                    px_atom_hit := '0';
                                    px_flag_hit := '1';
                                else
                                    px_atom_hit := '0';
                                    px_flag_hit := '0';

                                end if;
                               if roi_first_pixel = '1' then
                                    site_atom_hit(site_col) := px_atom_hit;
                                    site_flag_hit(site_col) := px_flag_hit;
                                else
                                    site_atom_hit(site_col) := site_atom_hit(site_col) or px_atom_hit;
                                    site_flag_hit(site_col) := site_flag_hit(site_col) or px_flag_hit;
                                end if;

                                if roi_last_pixel = '1' then
                                    if (site_atom_hit(site_col) = '1') or (px_atom_hit = '1') then
                                        grid_val <= '1';
                                        flag <= '0';
                                        atom_counter := atom_counter + 1;
                                        roi_results(site_row)(site_col) <='1';
                                    elsif (site_flag_hit(site_col) = '1') or (px_flag_hit = '1') then
                                        grid_val <= '0';
                                        flag <= '1';
                                        roi_results(site_row)(site_col) <='0';
                                    else
                                        grid_val <= '0';
                                        flag <= '0';
                                        roi_results(site_row)(site_col) <='0';
                                    end if;
                                end if;
                            end if;

                            if count = to_unsigned(img_width - 1, 8) then
                                count <= (others => '0');
                                if row < to_unsigned(img_height - 1, 8) then
                                    row <= row + 1;
                                 elsif row = to_unsigned(img_height - 1, 8) then
                                    row   <= (others => '0');
                                    qs_1<='1';
                                    STATE <= CONSTRUCT_TARGET;
                                end if;
                            end if;
                        end if;

                    when CONSTRUCT_TARGET =>
                    -- Very easy to add more targets. Just keep adding elsif statement in order of priority!
                        target_grid <= (others => (others => '0'));
                       -- if atom_counter >= 36 then
                        	---for r in 0 to 5 loop
                              ---  for c in 0 to 5 loop
                                ---    target_grid(r)(c)<= '1';
                              ---  end loop;
                           --- end loop;
                        ---elsif atom_counter >= 30 then
                        	---for r in 0 to 5 loop
                              ---  for c in 0 to 4 loop
                                 ---   target_grid(r)(c)<= '1';
                               --- end loop;
                           --- end loop;
                      ---  elsif atom_counter >= 25 then
                          ---  for r in 0 to 4 loop
                             ---   for c in 0 to 4 loop
                                ---    target_grid(r)(c)<= '1';
                               --- end loop;
                         ---   end loop;
                       --- elsif atom_counter>=16 then
                         ---   for r in 0 to 3 loop
                             --   for c in 0 to 3 loop
                                  --  target_grid(r)(c)<='1';
                              --  end loop;
                          --  end loop;
                        if atom_counter >= 4 then
                            for r in 0 to 1 loop
                                for c in 0 to 1 loop
                                    target_grid(r)(c) <= '1';
                                end loop;
                            end loop;

                        else
                            target_grid <= (others => (others => '0'));
                            --qs_4 <='1';
                        end if;
                        var_results := roi_results;
                        index:=0;
                        qs_2<='1';
                        STATE <= REARRANGE;

                    when REARRANGE =>
                        found_empty := false;
                        OUTER_R: for r in 0 to (grid_size -1) loop
                            OUTER_C: for c in 0 to (grid_size - 1) loop
                                if target_grid(r)(c) = '1' and var_results(r)(c) = '0' then
                                    found_empty := true;
                                    var_results(r)(c):='1';
                                    target_r <= r;
                                    target_c <= c;
                                    STATE <= SEARCH_DONOR;
                                    exit OUTER_R;
	                               end if;
                            end loop;
                        end loop;

                        if not found_empty then
                            roi_results <= var_results;
                            fifo_storage <= var_fifo;
                            fifo_count <= index;
                            i <= 0;
                            qs_3<='1';
                            STATE <= EXECUTE_MOVES;
                        end if;

                    when SEARCH_DONOR =>
                        INNER_R: for r_2 in 0 to (grid_size -1) loop
                            INNER_C: for c_2 in 0 to (grid_size -1) loop
                                if var_results(r_2)(c_2) = '1' and target_grid(r_2)(c_2) = '0' then
                                    var_results(r_2)(c_2) := '0';

                                    var_fifo(index).x_co     := std_logic_vector(TO_UNSIGNED(r_2, 8));
                                    var_fifo(index).y_co     := std_logic_vector(TO_UNSIGNED(c_2, 8));
                                    var_fifo(index).x_move_v := TO_SIGNED(target_r - r_2, 8);
                                    var_fifo(index).y_move_v := TO_SIGNED(target_c - c_2, 8);
                                    index := index + 1;
                                    STATE <= REARRANGE;
                                    exit INNER_R;
                                end if;
                           	end loop INNER_C;
                        end loop INNER_R;


                  when EXECUTE_MOVES =>                   
                    if Trigger='1' then
                        if i < fifo_count then
                            qs_4<='1';
                            --readout_s <= '1';
                            case phase is
                                when '0' =>  --send x or y coordinate depending on phase
                                    if toggle = '0' then
                                        x_addr_s <= SIGNED(fifo_storage(i).x_co);
                                        toggle <= '1';
                                    else
                                        x_addr_s <= SIGNED(fifo_storage(i).y_co);
                                        toggle <= '0';
                                        phase <= '1';
                                    end if;
                                    STATE <= DELAY;

                                when '1' =>  -- send move vector
                                    if toggle = '0' then
                                        x_addr_s <= fifo_storage(i).x_move_v;
                                        toggle <= '1';
                                    else
                                        x_addr_s <= fifo_storage(i).y_move_v;
                                        toggle <= '0';
                                        phase <= '0';
                                        i <= i + 1;
                                    end if;
                                    STATE <= DELAY;

                                when others => null;
                            end case;
                        else
                            readout_s <= '0';
                            x_addr_s <= TO_SIGNED(0, 8);
                        end if;
                    end if;


                   when DELAY => -- Just so we can readout signal easily. Adds a delay between subsequent address and instructions.
                        --readout_s <='0';
                        if delay_s =0 then
                        	readout_s<='1';
                        else
                        	readout_s<='0';
                        end if;
                        if delay_s < output_del then -- ~ separation between each signal, visible on scope.
                            delay_s <= delay_s + 1;
                        elsif delay_s = output_del then
                            delay_s <=0;
                            STATE <=EXECUTE_MOVES;
                        end if;

                    when others =>
                        STATE <= FINDING_1;
                end case;
            end if;
        end if;
    end process finding_ones;

    Q_1 <= qs_1;
    Q_2 <=qs_2;
    Q_3 <= qs_3;
    Q_4 <=qs_4;
    readout <= readout_s;
    dac_signal_14bit <= x_addr_s & "000000";

    dac_driver: process(clk, reset) 
    -- This produces The output signal on to both ports. If u wanted to separate x and y, use if statement.
    begin
        if reset = '0' then
            dac_dda   <= (others => '0');
            dac_state <= SEL_SETUP;
            dac_timer <= 0;
            dac_sel   <= '1';
            IQWRT  <= '0';
            IQSEL  <= '0';
            IQCLK <= '0';
            IQRESET  <= '0';

        elsif rising_edge(clk) then

            dac_dda <= dac_signal_14bit;
            if dac_timer < DAC_DWELL then
                dac_timer <= dac_timer + 1;
            else
                dac_timer <= 0;
                case dac_state is
                    when SEL_SETUP =>
                        -- datasheet: IQSEL must change while IQWRT & IQCLK are LOW
                        IQCLK <= '0'; -- Ensure signals are low prior to pulse
                        IQWRT <= '0';
                        IQRESET <='0';
                        IQSEL <= dac_sel;
                        dac_state <= DATA_SETUP;

                    when DATA_SETUP =>                     
                        dac_state <= CLK_HI;

                    when CLK_HI =>
                        IQCLK  <= '1';
                        dac_state <= WRT_HI;

                    when WRT_HI =>
                        IQWRT <= '1';
                        dac_state <= BOTH_LO;

                    when BOTH_LO =>
                        IQCLK  <= '0';
                        IQWRT <='0';
                        dac_state <= SWAP_CHAN;

                   when SWAP_CHAN =>
                        dac_sel <= not dac_sel;
                        dac_state <= SEL_SETUP;

                    when others =>
                    dac_state <= SEL_SETUP;
                end case;
            end if;
        end if;
    end process;

end architecture quantum_decoder;
