--------------------------------------------------------------------------------
--
-- Prova Finale (Progetto di Reti Logiche)
-- Prof. Fabio Salice - Anno 2020/2021
--
-- Paolo Longo (Codice Persona 10677668 Matricola 911983)
--
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;

entity project_reti_logiche is
  port (
    -- Inputs.
    i_clk     : in std_logic;                     -- Clock signal.
    i_rst     : in std_logic;                     -- Reset signal.
    i_start   : in std_logic;                     -- Start signal.
    i_data    : in std_logic_vector(7 downto 0);  -- Data received from the memory.
    -- Outputs.
    o_done    : out std_logic;                    -- Done signal.
    o_en      : out std_logic;                    -- Memory enable signal.
    o_we      : out std_logic;                    -- Memory mode signal (0-read, 1-write).
    o_data    : out std_logic_vector(7 downto 0); -- Data sent to the memory.
    o_address : out std_logic_vector(15 downto 0) -- Address to write/read from the memory.
  );
end entity;

architecture Behavior of project_reti_logiche is
  type STATE_TYPE is (
    START,            -- Waiting state:
                      --  • The start signal is '1'. (The
                      --     reset signal is assumed to be
                      --     used before the start signal).   -> READ_SIZE.
                      --  • The start signal is '0'.          -> START.

    READ_SIZE,        -- Read size state:
                      --  • Wait for the column size.         -> WAIT_READ_SIZE.
                      --  • Wait for the row size.            -> WAIT_READ_SIZE.
                      --  • Calculation of image bounds
                      --     and first pixel pre-fetch.       -> WAIT_READ_PIXEL.
                      --  • 0x0 image.                        -> DONE.

    WAIT_READ_SIZE,   -- Waiting state:
                      --  • Read the next size.               -> READ_SIZE.

    READ_PIXEL,       -- Read pixel state:
                      --  • A pixel is read.                  -> WAIT_READ_PIXEL.
                      --  • All pixels have been examined.
                      --     Calculation of the pixels bounds
                      --     and pre-fetch first pixel.       -> WAIT_READ_PIXEL.
                      --  • All pixels have been written.     -> DONE.

    WAIT_READ_PIXEL,  -- Waiting state:
                      --  • Searching for pixels bounds.      -> WAIT_READ_PIXEL.
                      --  • Processing the pixels.            -> WRITE_PIXEL.

    WRITE_PIXEL,      -- Write pixel state:
                      --  • A pixel is processed.             -> WAIT_WRITE_PIXEL.

    WAIT_WRITE_PIXEL, -- Waiting state.
                      --  • The pixel is written.             -> READ_PIXEL.

    DONE              -- Waiting state:
                      --  • The start signal is '0'.          -> START.
                      --  • The start signal is '1'.          -> DONE.
  );

  -- State register.
  signal state : STATE_TYPE := START;

  -- State flag registers.
  signal has_column_size  : boolean := false; -- READ_SIZE.
  signal has_row_size     : boolean := false; -- READ_SIZE.
  signal has_pixels_range : boolean := false; -- READ_PIXEL, WAIT_READ_PIXEL.

  -- Pixels range registers.
  signal MAX_PIXEL_VALUE : unsigned(7 downto 0) := (others => '0'); -- Init at 0.
  signal MIN_PIXEL_VALUE : unsigned(7 downto 0) := (others => '1'); -- Init at 255.

  -- Process registers.
  signal last_pixel_address : std_logic_vector(15 downto 0) := (others => '0'); -- (2) to (128x128 + 1).
  signal current_pixel      : std_logic_vector(15 downto 0) := (others => '0'); -- from (1) up to (128x128).

  -- shift_level(value) => 8 - floor(Log2(value)).
  -- We are not interested in cases where there is only one pixel value, and
  -- the shift level is 8, since all the pixels would be set to 0.
  function shift_level (value: unsigned(7 downto 0)) return unsigned is
  begin
    -- Find the hightest.
    if    value(7) = '1' then return "001";
    elsif value(6) = '1' then return "010";
    elsif value(5) = '1' then return "011";
    elsif value(4) = '1' then return "100";
    elsif value(3) = '1' then return "101";
    elsif value(2) = '1' then return "110";
    elsif value(1) = '1' then return "111";
    -- Case with don't care about.
    else                      return "000";
    end if;
  end function;

  -- Init the read loop of pixel.
  procedure init_loop (
    signal o_address      : out std_logic_vector(15 downto 0);
    signal current_pixel  : out std_logic_vector(15 downto 0)) is
  begin
    -- Init the adresses.
    o_address     <= "0000000000000010";
    current_pixel <= "0000000000000001";
  end procedure;

begin
  transitions: process (i_clk)
    -- Variable to hold value between calcs.
    variable var : unsigned(15 downto 0) := (others => '0');
  begin
    if rising_edge(i_clk) then
      -- Default output signals.
      o_done    <= '0';
      o_en      <= '0';
      o_we      <= '0';
      o_data    <= (others => '0');
      o_address <= (others => '0');
      -- Check for the reset signal.
      if i_rst = '1' then
        -- Reset the state.
        state <= START;
      else
        case state is
          when START =>
            -- The reset signal is supposed to be used only before the first
            -- image so we need to reset every register before starting.
            -- Reset state flag registers.
            has_column_size   <= false;
            has_row_size      <= false;
            has_pixels_range  <= false;
            -- Reset pixel range.
            MAX_PIXEL_VALUE <= (others => '0');
            MIN_PIXEL_VALUE <= (others => '1');
            -- Reset process registers.
            last_pixel_address  <= (others => '0');
            current_pixel       <= (others => '0');
            -- Set next state.
            if i_start = '1' then
              -- Start the process.
              state <= READ_SIZE;
            else
              -- Wait the start signal.
              state <= START;
            end if;

          when READ_SIZE =>
            -- Enable the memory.
            o_en <= '1';
            if not has_column_size then
              -- Read the column size.
              o_address <= "0000000000000000";
              state <= WAIT_READ_SIZE;
              -- Set the flag.
              has_column_size <= true;
            elsif not has_row_size then
              -- Save the column size.
              last_pixel_address <= "00000000" & i_data;
              -- Read the row size.
              o_address <= "0000000000000001";
              state <= WAIT_READ_SIZE;
              -- Set the flag.
              has_row_size <= true;
            else
              -- Calc the number of pixels.
              var := unsigned(last_pixel_address(7 downto 0)) * unsigned(i_data);
              -- Check if there are pixels.
              if not (var = "0000000000000000") then
                -- Set the limit.
                last_pixel_address <= std_logic_vector(var + 1);
                -- Init the loop.
                init_loop(o_address, current_pixel);
                state <= WAIT_READ_PIXEL;
              else
                -- Set done signal.
                o_done <= '1';
                -- Set the next state.
                state <= DONE;
              end if;
            end if;

          when WAIT_READ_SIZE =>
            -- Set the next state.
            state <= READ_SIZE;

          when READ_PIXEL =>
            -- Calc MAX / MIN.
            if not has_pixels_range then
              -- Update MAX_PIXEL_VALUE.
              if MAX_PIXEL_VALUE < unsigned(i_data) then
                MAX_PIXEL_VALUE <= unsigned(i_data);
              end if;
              -- Update MIN_PIXEL_VALUE.
              if MIN_PIXEL_VALUE > unsigned(i_data) then
                MIN_PIXEL_VALUE <= unsigned(i_data);
              end if;
            end if;

            -- Calc the new address.
            var := unsigned(current_pixel) + 1;
            -- Check if all the pixels have been read.
            if not (std_logic_vector(var) = last_pixel_address) then
              -- Update the addresses.
              current_pixel <= std_logic_vector(var);
              o_address <= std_logic_vector(var + 1);
              -- Enable the memory.
              o_en <= '1';
              -- Set the next state.
              state <= WAIT_READ_PIXEL;
            else
              if not has_pixels_range then
                -- Update flag.
                has_pixels_range <= true;
                -- Enable the memory.
                o_en <= '1';
                -- Init the loop.
                init_loop(o_address, current_pixel);
                state <= WAIT_READ_PIXEL;
              else
                -- Set done signal.
                o_done <= '1';
                -- Set the next state.
                state <= DONE;
              end if;
            end if;

          when WAIT_READ_PIXEL =>
            if not has_pixels_range then
              -- Set the next state.
              state <= READ_PIXEL;
            else
              -- Set the next state.
              state <= WRITE_PIXEL;
            end if;

          when WRITE_PIXEL =>
            -- Enable the memory.
            o_en <= '1';
            -- Write mode.
            o_we <= '1';
            -- Set the output address.
            o_address <= std_logic_vector(unsigned(current_pixel) + unsigned(last_pixel_address));
            -- Pixel value processing.
            var := ("00000000" & (unsigned(i_data) - MIN_PIXEL_VALUE))
              sll to_integer(shift_level(MAX_PIXEL_VALUE - MIN_PIXEL_VALUE + 1));
            -- min(new_pixel, 255).
            if var <= 255 then
              o_data <= std_logic_vector(var(7 downto 0));
            else
              o_data <= "11111111";
            end if;
            -- Set the next state.
            state <= WAIT_WRITE_PIXEL;

          when WAIT_WRITE_PIXEL =>
            -- Set the next state.
            state <= READ_PIXEL;

          when DONE =>
            if i_start = '0' then
              -- Set the next state.
              state <= START;
            else
              -- Set done signal.
              o_done <= '1';
              -- Set the next state.
              state <= DONE;
            end if;

        end case;
      end if;
    end if;
  end process;
end architecture;