--------------------------------------------------------------------------------
-- Booth's Multiplication Algorithm - RISC-V RV32 Compatible
--------------------------------------------------------------------------------
-- Implements Booth's radix-2 algorithm for signed 32-bit multiplication.
-- Produces a 64-bit result (compatible with RV32M MUL/MULH instructions).
--
-- Interface:
--   clk        : Clock
--   rst        : Synchronous reset (active high)
--   start      : Pulse high for 1 cycle to begin multiplication
--   multiplicand: 32-bit signed input (rs1)
--   multiplier  : 32-bit signed input (rs2)
--   result_lo  : Lower 32 bits of product  (MUL  result)
--   result_hi  : Upper 32 bits of product  (MULH result)
--   done       : Asserted when result is valid
--   busy       : Asserted while computation is in progress
--
-- Latency: 33 clock cycles (1 init + 32 iterations)
-- Handles full signed 32-bit range including -2^31
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity booth_multiplier_rv32 is
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        start        : in  std_logic;
        multiplicand : in  std_logic_vector(31 downto 0);  -- rs1
        multiplier   : in  std_logic_vector(31 downto 0);  -- rs2
        result_lo    : out std_logic_vector(31 downto 0);   -- MUL  result
        result_hi    : out std_logic_vector(31 downto 0);   -- MULH result
        done         : buffer std_logic;
        busy         : out std_logic
    );
end entity booth_multiplier_rv32;

architecture rtl of booth_multiplier_rv32 is

    -- FSM states
    type state_t is (S_IDLE, S_COMPUTE, S_DONE);
    signal state : state_t;

    -- Internal registers
    -- Accumulator (A) : upper partial product, 33 bits (extra sign bit)
    -- Q register      : multiplier shifted right each cycle, 32 bits
    -- Q_minus1        : extra bit for Booth encoding
    -- M register      : multiplicand, 33 bits (sign-extended)
    signal A        : signed(32 downto 0);   -- 33-bit accumulator
    signal Q        : signed(31 downto 0);   -- 32-bit multiplier register
    signal Q_minus1 : std_logic;             -- Booth extra bit
    signal M        : signed(32 downto 0);   -- 33-bit sign-extended multiplicand

    -- Iteration counter
    signal count    : unsigned(5 downto 0);  -- counts 0..31 (32 iterations)
    signal busy_reg      : std_logic;
    signal start_inhibit : std_logic := '0';

begin

    -- busy: combinacional quando start=1 em S_IDLE (eager)
    -- Garante que muldiv_busy sobe no mesmo ciclo que ex_startMul,
    -- evitando necessidade de stall especial para o ciclo K.
    busy <= '1' when (state = S_IDLE and start = '1' and start_inhibit = '0') else busy_reg;

    process(clk)
        variable A_next : signed(32 downto 0);
        variable concat : signed(65 downto 0);  -- {A, Q, Q_minus1} for shift
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state    <= S_IDLE;
                A        <= (others => '0');
                Q        <= (others => '0');
                Q_minus1 <= '0';
                M        <= (others => '0');
                count    <= (others => '0');
                done     <= '0';
                busy_reg <= '0';
            else
                case state is

                    when S_IDLE =>
                        done <= '0';
                        -- Clear inhibit when start falls
                        if start = '0' then
                            start_inhibit <= '0';
                        end if;
                        -- Only start new operation if inhibit is clear
                        if start = '1' and start_inhibit = '0' then
                            -- Initialize registers
                            A        <= (others => '0');
                            Q        <= signed(multiplier);
                            Q_minus1 <= '0';
                            -- Sign-extend multiplicand to 33 bits
                            M <= resize(signed(multiplicand), 33);
                            count <= (others => '0');
                            state <= S_COMPUTE;
                            busy_reg  <= '1';
                        end if;

                    when S_COMPUTE =>
                        -- Booth encoding: examine {Q(0), Q_minus1}
                        --   "01" -> A = A + M  (transition 0->1: end of string of 1s)
                        --   "10" -> A = A - M  (transition 1->0: start of string of 1s)
                        --   "00","11" -> no operation
                        A_next := A;

                        case std_logic_vector'(Q(0) & Q_minus1) is
                            when "01" =>
                                A_next := A + M;
                            when "10" =>
                                A_next := A - M;
                            when others =>
                                A_next := A;
                        end case;

                        -- Arithmetic right shift {A_next, Q, Q_minus1} by 1
                        concat := A_next & Q & Q_minus1;
                        -- Arithmetic shift right preserves sign (MSB of A_next)
                        concat := shift_right(concat, 1);

                        A        <= concat(65 downto 33);
                        Q        <= concat(32 downto 1);
                        Q_minus1 <= concat(0);

                        -- Increment counter
                        if count = to_unsigned(31, 6) then
                            state <= S_DONE;
                        else
                            count <= count + 1;
                        end if;

                    when S_DONE =>
                        -- Output the 64-bit product: {A[31:0], Q[31:0]}
                        done          <= '1';
                        busy_reg      <= '0';
                        start_inhibit <= '1';  -- previne reinicio quando start ainda esta alto
                        state         <= S_IDLE;

                end case;
            end if;
        end if;
    end process;

    -- Result outputs (active when done='1')
    result_hi <= std_logic_vector(A(31 downto 0));
    result_lo <= std_logic_vector(Q);

end architecture rtl;
