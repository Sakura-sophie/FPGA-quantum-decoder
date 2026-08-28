
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use STD.textio.all;
use IEEE.std_logic_textio.all;

entity tb_my_FPGA is
end entity tb_my_FPGA;

architecture sim of tb_my_FPGA is

    constant CLK_PERIOD  : time := 10 ns;       -- 100 MHz system clk
    constant PIXEL_RATE  : time := 10 us;       -- Time interval between pixels
    constant IMG_WIDTH   : integer := 12;
    constant IMG_HEIGHT  : integer := 12;

    signal clk             : std_logic := '0';
    signal reset           : std_logic := '0';  
    signal img_bit_stream : std_logic_vector(13 downto 0) := (others => '0');
    signal valid           : std_logic := '0';
    signal readout         : std_logic;
    signal Trigger         : std_logic :='0';
    signal Q_1, Q_2, Q_3, Q_4 : std_logic;
    signal dac_dda         : signed(13 downto 0);
    signal IQWRT, IQSEL, IQCLK, IQRESET : std_logic;

    signal sim_done : boolean := false;

begin

    uut : entity work.my_FPGA
        generic map (
            img_width  => IMG_WIDTH,
            img_height => IMG_HEIGHT
        )
        port map (
            clk            => clk,
            reset          => reset,
            img_bit_stream => img_bit_stream,
            valid          => valid,
            readout        => readout,
            Trigger       => Trigger,
            Q_1            => Q_1,
            Q_2            => Q_2,
            Q_3            => Q_3,
            Q_4            => Q_4,
            dac_dda        => dac_dda,
            IQWRT          => IQWRT,
            IQSEL          => IQSEL,
            IQCLK          => IQCLK,
            IQRESET        => IQRESET
        );

    -- 100 MHz Clock Generator
    clk_gen : process
    begin
        while not sim_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- Reset Generator
    reset_gen : process
    begin
        reset <= '0';
        wait for 200 ns;
        wait until rising_edge(clk);
        reset <= '1';
        wait;
    end process;

    -- Stimulus Process: Drives data at fixed PIXEL_RATE intervals
    stim : process
        file     img_file : text open read_mode is "myfile.txt";
        variable line_v   : line;
        variable data_v   : std_logic_vector(13 downto 0);
        variable pixel_n  : integer := 0;
    begin
        wait until reset = '1';

        while not endfile(img_file) loop
            readline(img_file, line_v);
            read(line_v, data_v);

            -- Align to system clock edge first
            --wait until rising_edge(clk);
            wait for 20 ns;
            img_bit_stream <= data_v;
            valid          <= '1';
            
            --wait until rising_edge(clk);
            wait for 20 ns;
            valid          <= '0';

            pixel_n := pixel_n + 1;

            -- Wait the remaining duration of the fixed interval before sending next pixel
            --wait for PIXEL_RATE - (2 * CLK_PERIOD);
        end loop;
        
        wait for 1 us;
        Trigger <='1';
        wait for 50 us;
        sim_done <= true;
        wait;
    end process;

end architecture sim;
