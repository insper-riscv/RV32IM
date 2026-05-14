--------------------------------------------------------------------------------
-- Non-Restoring Division Algorithm - RISC-V RV32M Compatible
--------------------------------------------------------------------------------
-- Suporta as 4 instruções de divisão do RV32M:
--   is_unsigned = '0' : DIV  / REM  (operandos signed, truncamento p/ zero)
--   is_unsigned = '1' : DIVU / REMU (operandos unsigned)
--
-- Casos especiais (RISC-V ISA Spec):
--   SIGNED (is_unsigned='0'):
--     - Divisão por zero : quotient = -1 (0xFFFFFFFF), remainder = dividend
--     - Overflow (-2^31 / -1): quotient = -2^31, remainder = 0
--     - Sinal do resto segue o sinal do dividendo
--   UNSIGNED (is_unsigned='1'):
--     - Divisão por zero : quotient = 0xFFFFFFFF (2^32-1), remainder = dividend
--     - Não existe caso de overflow
--
-- Interface:
--   clk         : Clock
--   rst         : Synchronous reset (active high)
--   start       : Pulse high for 1 cycle to begin division
--   is_unsigned : '0' = signed (DIV/REM), '1' = unsigned (DIVU/REMU)
--   dividend    : 32-bit input (rs1)
--   divisor     : 32-bit input (rs2)
--   quotient    : 32-bit result (DIV/DIVU result)
--   remainder   : 32-bit result (REM/REMU result)
--   done        : Asserted when result is valid
--   busy        : Asserted while computation is in progress
--   div_by_zero : Asserted if divisor was zero
--   overflow    : Asserted if signed overflow occurred (only for signed mode)
--
-- Latency: 34 clock cycles (1 init + 32 iterations + 1 correction)
--          2 cycles for special cases (div-by-zero, overflow)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity non_restoring_divider_rv32 is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        start       : in  std_logic;
        is_unsigned : in  std_logic;                      -- '0'=DIV/REM, '1'=DIVU/REMU
        dividend    : in  std_logic_vector(31 downto 0);  -- rs1
        divisor     : in  std_logic_vector(31 downto 0);  -- rs2
        quotient    : out std_logic_vector(31 downto 0);  -- DIV/DIVU result
        remainder   : out std_logic_vector(31 downto 0);  -- REM/REMU result
        done        : buffer std_logic;
        busy        : out std_logic;
        div_by_zero : out std_logic;
        overflow    : out std_logic
    );
end entity non_restoring_divider_rv32;

architecture rtl of non_restoring_divider_rv32 is

    -- FSM states
    type state_t is (S_IDLE, S_SPECIAL, S_COMPUTE, S_CORRECT, S_ADJUST_SIGN, S_DONE);
    signal state : state_t;

    -- Internal working registers (always operate on absolute/unsigned values)
    signal A     : signed(32 downto 0);   -- 33-bit partial remainder (extra sign bit)
    signal Q     : unsigned(31 downto 0); -- quotient being built
    signal M     : signed(32 downto 0);   -- 33-bit divisor (always positive here)
    signal count : unsigned(5 downto 0);  -- iteration counter 0..31

    -- Sign tracking for signed mode
    signal dividend_neg : std_logic;  -- original dividend was negative
    signal divisor_neg  : std_logic;  -- original divisor was negative
    signal op_unsigned  : std_logic;  -- latched copy of is_unsigned

    -- Special case detection
    signal detect_div_by_zero : std_logic;
    signal detect_overflow    : std_logic;

    -- Internal result registers
    signal q_result : std_logic_vector(31 downto 0);
    signal r_result : std_logic_vector(31 downto 0);

    -- Constants
    constant ALL_ONES : std_logic_vector(31 downto 0) := x"FFFFFFFF";
    constant INT_MIN  : std_logic_vector(31 downto 0) := x"80000000";

    signal busy_reg      : std_logic := '0';
    signal start_inhibit : std_logic := '0';

begin

    -- busy eager: combinacional quando start=1 em S_IDLE
    -- Garante que muldiv_busy sobe no mesmo ciclo que ex_startMul no pipeline.
    busy <= '1' when (state = S_IDLE and start = '1' and start_inhibit = '0') else busy_reg;

    -------------------------------------------------------------------------
    -- Special case detection (combinational)
    -------------------------------------------------------------------------
    detect_div_by_zero <= '1' when unsigned(divisor) = 0 else '0';

    -- Signed overflow: only possible in signed mode, when dividend = -2^31
    -- and divisor = -1. In unsigned mode this is just a normal division.
    detect_overflow <= '1' when is_unsigned = '0'
                                and dividend = INT_MIN
                                and divisor  = ALL_ONES
                       else '0';

    -------------------------------------------------------------------------
    -- Main sequential process
    -------------------------------------------------------------------------
    process(clk)
        variable A_shifted : signed(32 downto 0);
        variable A_next    : signed(32 downto 0);
        variable abs_dividend_v : unsigned(31 downto 0);
        variable abs_divisor_v  : unsigned(31 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state        <= S_IDLE;
                A            <= (others => '0');
                Q            <= (others => '0');
                M            <= (others => '0');
                count        <= (others => '0');
                dividend_neg <= '0';
                divisor_neg  <= '0';
                op_unsigned  <= '0';
                done         <= '0';
                busy_reg     <= '0';
                q_result     <= (others => '0');
                r_result     <= (others => '0');
            else
                case state is

                    -----------------------------------------------------------
                    -- IDLE: aguarda start
                    -----------------------------------------------------------
                    when S_IDLE =>
                        done <= '0';
                        -- Clear inhibit when start falls
                        if start = '0' then
                            start_inhibit <= '0';
                        end if;
                        -- Only start new operation if inhibit is clear
                        if start = '1' and start_inhibit = '0' then
                            -- Latch mode
                            op_unsigned <= is_unsigned;

                            -- Check special cases
                            if detect_div_by_zero = '1' or detect_overflow = '1' then
                                state <= S_SPECIAL;
                                busy_reg <= '1';

                                if is_unsigned = '1' then
                                    dividend_neg <= '0';
                                    divisor_neg  <= '0';
                                else
                                    dividend_neg <= dividend(31);
                                    divisor_neg  <= divisor(31);
                                end if;
                            else
                                busy_reg <= '1';

                                -----------------------------------------------
                                -- Compute absolute values / pass-through
                                -----------------------------------------------
                                if is_unsigned = '1' then
                                    -- Unsigned: use values directly
                                    dividend_neg <= '0';
                                    divisor_neg  <= '0';
                                    abs_dividend_v := unsigned(dividend);
                                    abs_divisor_v  := unsigned(divisor);
                                else
                                    -- Signed: record signs, take absolute values
                                    dividend_neg <= dividend(31);
                                    divisor_neg  <= divisor(31);

                                    if signed(dividend) < 0 then
                                        abs_dividend_v := unsigned(-signed(dividend));
                                    else
                                        abs_dividend_v := unsigned(dividend);
                                    end if;

                                    if signed(divisor) < 0 then
                                        abs_divisor_v := unsigned(-signed(divisor));
                                    else
                                        abs_divisor_v := unsigned(divisor);
                                    end if;
                                end if;

                                -- Initialize datapath
                                A     <= (others => '0');
                                Q     <= abs_dividend_v;
                                M     <= signed('0' & std_logic_vector(abs_divisor_v));
                                count <= (others => '0');
                                state <= S_COMPUTE;
                            end if;
                        end if;

                    -----------------------------------------------------------
                    -- SPECIAL: handle div-by-zero and signed overflow
                    -----------------------------------------------------------
                    when S_SPECIAL =>
                        if detect_div_by_zero = '1' then
                            -- RISC-V spec: both signed and unsigned
                            -- quotient = all 1s, remainder = dividend
                            q_result <= ALL_ONES;
                            r_result <= dividend;
                        else
                            -- Signed overflow: -2^31 / -1
                            -- quotient = -2^31 (wraps), remainder = 0
                            q_result <= INT_MIN;
                            r_result <= (others => '0');
                        end if;
                        state <= S_DONE;

                    -----------------------------------------------------------
                    -- COMPUTE: 32 iterations of non-restoring division
                    -----------------------------------------------------------
                    when S_COMPUTE =>
                        -- Step 1: Left shift {A, Q} by 1
                        A_shifted := A(31 downto 0) & Q(31);

                        -- Step 2: A = A +/- M based on sign of shifted A
                        if A_shifted >= 0 then
                            A_next := A_shifted - M;
                        else
                            A_next := A_shifted + M;
                        end if;

                        A <= A_next;

                        -- Shift Q left, set LSB from result sign
                        if A_next >= 0 then
                            Q <= Q(30 downto 0) & '1';
                        else
                            Q <= Q(30 downto 0) & '0';
                        end if;

                        if count = to_unsigned(31, 6) then
                            state <= S_CORRECT;
                        else
                            count <= count + 1;
                        end if;

                    -----------------------------------------------------------
                    -- CORRECT: restore remainder if negative
                    -----------------------------------------------------------
                    when S_CORRECT =>
                        if A < 0 then
                            A <= A + M;
                        end if;
                        state <= S_ADJUST_SIGN;

                    -----------------------------------------------------------
                    -- ADJUST_SIGN: apply sign correction (signed mode only)
                    -----------------------------------------------------------
                    when S_ADJUST_SIGN =>
                        if op_unsigned = '1' then
                            -- Unsigned: resultado direto, sem ajuste de sinal
                            q_result <= std_logic_vector(Q);
                            r_result <= std_logic_vector(A(31 downto 0));
                        else
                            -- Signed: quotient sign = dividend_sign XOR divisor_sign
                            if (dividend_neg xor divisor_neg) = '1' then
                                q_result <= std_logic_vector(-signed(Q));
                            else
                                q_result <= std_logic_vector(Q);
                            end if;

                            -- Signed: remainder sign = dividend sign
                            if dividend_neg = '1' then
                                r_result <= std_logic_vector(-A(31 downto 0));
                            else
                                r_result <= std_logic_vector(A(31 downto 0));
                            end if;
                        end if;

                        state <= S_DONE;

                    -----------------------------------------------------------
                    -- DONE: assert done, return to idle
                    -----------------------------------------------------------
                    when S_DONE =>
                        done          <= '1';
                        start_inhibit <= '1';
                        busy_reg <= '0';
                        state <= S_IDLE;

                end case;
            end if;
        end if;
    end process;

    -- Output assignments
    quotient    <= q_result;
    remainder   <= r_result;
    div_by_zero <= detect_div_by_zero;
    overflow    <= detect_overflow;

end architecture rtl;
