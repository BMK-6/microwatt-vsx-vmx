library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;

entity register_file is
    generic (
        SIM : boolean := false;
        HAS_FPU : boolean := true;
    	-- Revert to false before VSX decode integration
      	TEST_FPU2_PATH : boolean := true;
        -- Non-zero to enable log data collection
        LOG_LENGTH : natural := 0
	        );
    port(
        clk           : in std_logic;
        stall         : in std_ulogic;

        d1_in         : in Decode1ToRegisterFileType;
        d_in          : in Decode2ToRegisterFileType;
        d_out         : out RegisterFileToDecode2Type;

        w_in          : in WritebackToRegisterFileType;

        dbg_gpr_req   : in std_ulogic;
        dbg_gpr_ack   : out std_ulogic;
        dbg_gpr_addr  : in gspr_index_t;
        dbg_gpr_data  : out std_ulogic_vector(63 downto 0);

        -- debug
        sim_dump      : in std_ulogic;
        sim_dump_done : out std_ulogic;

        log_out       : out std_ulogic_vector(71 downto 0)
        );
end entity register_file;

architecture behaviour of register_file is
    type regfile is array(0 to 63) of std_ulogic_vector(63 downto 0);
    signal registers : regfile := (others => (others => '0'));
    signal lo_registers : regfile := (others => (others => '0')); --VSX,FPR and VSR lo
    signal hi_registers : regfile := (others => (others => '0')); --VSX,FPR and VSR hi
    signal dbg_data : std_ulogic_vector(63 downto 0);
    signal dbg_ack : std_ulogic;
    signal dbg_gpr_done : std_ulogic;
    signal addr_1_reg : gspr_index_t;
    signal addr_2_reg : gspr_index_t;
    signal addr_3_reg : gspr_index_t;
    signal rd_2 : std_ulogic;
    signal fwd_1 : std_ulogic;
    signal fwd_2 : std_ulogic;
    signal fwd_3 : std_ulogic;
    signal data_1 : std_ulogic_vector(127 downto 0);
    signal data_2 : std_ulogic_vector(127 downto 0);
    signal data_3 : std_ulogic_vector(127 downto 0);
    signal prev_write_data : std_ulogic_vector(63 downto 0);
    signal prev_write_data_hi : std_ulogic_vector(63 downto 0);



begin
    -- synchronous reads and writes
    register_write_0: process(clk)
        variable a_addr, b_addr, c_addr : gspr_index_t;
        variable w_addr : gspr_index_t;
        variable b_enable : std_ulogic;
	variable gr_addr :gpr_index_t;
	variable fr_addr :fpr_index_t;
	variable fa_addr,fb_addr,fc_addr:fpr_index_t;
	variable ga_addr,gb_addr,gc_addr:gpr_index_t;
    begin
        if rising_edge(clk) then
            if w_in.write_enable = '1' then
                w_addr :=  w_in.write_reg;
		gr_addr:= gspr_to_gpr(w_in.write_reg);
		fr_addr:= gspr_to_fpr(w_in.write_reg);
                if HAS_FPU and w_addr(6) = '1' then
		-- synthesis off / simulation only
			if TEST_FPU2_PATH then
    				lo_registers(to_integer(unsigned(fr_addr))) <= w_in.write_data_hi;  -- test: route FP through hi path
				report "Writing FPR " & to_hstring(fr_addr) & " " & to_hstring(w_in.write_data_hi);
		    			assert not(is_x(w_in.write_data_hi)) and not(is_x(w_in.write_reg)) severity failure;

    				hi_registers(to_integer(unsigned(fr_addr))) <= (others => '0');
				
			else
    				lo_registers(to_integer(unsigned(fr_addr))) <= w_in.write_data;     -- correct architectural state
				  report "Writing FPR " & to_hstring(fr_addr) & " " & to_hstring(w_in.write_data);
		    			assert not(is_x(w_in.write_data)) and not(is_x(w_in.write_reg)) severity failure;

   				hi_registers(to_integer(unsigned(fr_addr))) <= w_in.write_data_hi;
				  report "Writing VSR " & to_hstring(fr_addr) & " " & to_hstring(w_in.write_data_hi);
		    			assert not(is_x(w_in.write_data_hi)) and not(is_x(w_in.write_reg)) severity failure;

				end if;				
                else
                    w_addr(6) := '0';
                    report "Writing GPR " & to_hstring(gr_addr) & " " & to_hstring(w_in.write_data);
		    assert not(is_x(w_in.write_data)) and not(is_x(w_in.write_reg)) severity failure;
                	registers(to_integer(unsigned(gr_addr))) <= w_in.write_data;
                end if;
            end if;

            a_addr := d1_in.reg_1_addr;
            b_addr := d1_in.reg_2_addr;
            c_addr := d1_in.reg_3_addr;
            b_enable := d1_in.read_2_enable;
            if stall = '1' then
                a_addr := addr_1_reg;
                b_addr := addr_2_reg;
                c_addr := addr_3_reg;
                b_enable := rd_2;
            else
                addr_1_reg <= a_addr;
                addr_2_reg <= b_addr;
                addr_3_reg <= c_addr;
                rd_2 <= b_enable;
            end if;

            fwd_1 <= '0';
            fwd_2 <= '0';
            fwd_3 <= '0';
            if w_in.write_enable = '1' then
                if w_addr = a_addr then
                    fwd_1 <= '1';
                end if;
                if w_addr = b_addr then
                    fwd_2 <= '1';
                end if;
                if w_addr = c_addr then
                    fwd_3 <= '1';
                end if;
            end if;

            -- Do debug reads to GPRs and FPRs using the B port when it is not in use
            if dbg_gpr_req = '1' then
                if b_enable = '0' then
                    b_addr :=  dbg_gpr_addr(5)&'0'& dbg_gpr_addr(4 downto 0);
                    dbg_gpr_done <= '1';
                end if;
            else
                dbg_gpr_done <= '0';
            end if;

            if not HAS_FPU then
                -- Make it obvious that we only want 32 GSPRs for a no-FPU implementation
                a_addr(6) := '0';
                b_addr(6) := '0';
                c_addr(6) := '0';
            end if;
	    ga_addr:=gspr_to_gpr(a_addr);
	    gb_addr:=gspr_to_gpr(b_addr);
	    gc_addr:=gspr_to_gpr(c_addr);
	    fa_addr:=gspr_to_gpr(a_addr);
	    fb_addr:=gspr_to_gpr(b_addr);
	    fc_addr:=gspr_to_gpr(c_addr);

	    if is_X(a_addr) then
		data_1(63 downto 0) <= (others => 'X');
	    elsif (HAS_FPU and a_addr(6) = '1' )then
		data_1(63 downto 0)   <= lo_registers(to_integer(unsigned (fa_addr)));
	      	data_1(127 downto 64) <= hi_registers(to_integer(unsigned (fa_addr))); 	
	    else
		data_1(63 downto 0) <= registers(to_integer(unsigned(ga_addr)));
	    end if;
	    if is_X(b_addr) then
		data_2(63 downto 0) <= (others => 'X');
	    elsif (HAS_FPU and b_addr(6) = '1' )then
		data_2(63 downto 0)  <= lo_registers(to_integer(unsigned(fb_addr)));
		data_2(127 downto 64)<= hi_registers(to_integer(unsigned(fb_addr)));
	    else
		data_2(63 downto 0) <= registers(to_integer(unsigned(gb_addr)));
	    end if;
	    if is_X(c_addr) then
		data_3(63 downto 0) <= (others => 'X');
	    elsif (HAS_FPU and c_addr(6) = '1' )then
		data_3(63 downto 0)   <= lo_registers(to_integer(unsigned(fc_addr)));
		data_3(127 downto 64) <= hi_registers(to_integer(unsigned(fc_addr)));
	    else
		data_3(63 downto 0) <= registers(to_integer(unsigned(gc_addr)));
	    end if;

            prev_write_data <= w_in.write_data;
	    prev_write_data_hi <=w_in.write_data_hi;
    end if;
    end process register_write_0;

    -- asynchronous forwarding of write data
    register_read_0: process(all)
        variable out_data_1 : std_ulogic_vector(63 downto 0);
        variable out_data_2 : std_ulogic_vector(63 downto 0);
        variable out_data_3 : std_ulogic_vector(63 downto 0);
	variable out_data_1_hi : std_ulogic_vector(63 downto 0);
        variable out_data_2_hi : std_ulogic_vector(63 downto 0);
        variable out_data_3_hi : std_ulogic_vector(63 downto 0);


    begin
        out_data_1 := data_1(63 downto 0);
        out_data_2 := data_2(63 downto 0);
        out_data_3 := data_3(63 downto 0);
	
	out_data_1_hi := data_1(127 downto 64);
        out_data_2_hi := data_2(127 downto 64);
        out_data_3_hi := data_3(127 downto 64);

        if fwd_1 = '1' then
	    if TEST_FPU2_PATH and addr_1_reg(6) = '1' then
        	out_data_1     := prev_write_data_hi;
        	out_data_1_hi  := prev_write_data;
            else
            	out_data_1 := prev_write_data;
	    	out_data_1_hi := prev_write_data_hi;
    	    end if;
        end if;
        if fwd_2 = '1' then
	   if TEST_FPU2_PATH and addr_2_reg(6) = '1' then
        	out_data_2     := prev_write_data_hi;
        	out_data_2_hi  := prev_write_data;
    	   else
            out_data_2 := prev_write_data;
	    out_data_2_hi := prev_write_data_hi;
	   end if;
        end if;
        if fwd_3 = '1' then
	   if TEST_FPU2_PATH and addr_3_reg(6) = '1' then
        	out_data_3     := prev_write_data_hi;
        	out_data_3_hi  := prev_write_data;
    	   else
            out_data_3 := prev_write_data;
	    out_data_3_hi := prev_write_data_hi;
    	   end if;	
        end if;

        if d_in.read1_enable = '1' then
            report "Reading GPR " & to_hstring(addr_1_reg) & " " & to_hstring(out_data_1);
        end if;
        if d_in.read2_enable = '1' then
            report "Reading GPR " & to_hstring(addr_2_reg) & " " & to_hstring(out_data_2);
        end if;
        if d_in.read3_enable = '1' then
            report "Reading GPR " & to_hstring(addr_3_reg) & " " & to_hstring(out_data_3);
        end if;
		
   
	 if d_in.read1_enable = '1' then
            report "Reading VR " & to_hstring(addr_1_reg) & " " & to_hstring(out_data_1_hi);
        end if;
        if d_in.read2_enable = '1' then
            report "Reading VR " & to_hstring(addr_2_reg) & " " & to_hstring(out_data_2_hi);
        end if;
        if d_in.read3_enable = '1' then
            report "Reading VR " & to_hstring(addr_3_reg) & " " & to_hstring(out_data_3_hi);
        end if;


-- sanity check: FP intent vs address usage (only check enabled operands)
	assert not (
    		 d1_in.is_insn_float = '0' and
    		  (
        	  (d1_in.read_1_enable = '1' and d1_in.reg_1_addr(5) = '1') or
        	  (d1_in.read_2_enable = '1' and d1_in.reg_2_addr(5) = '1') or
       		  (d1_in.read_3_enable = '1' and d1_in.reg_3_addr(5) = '1')
    		  )
		 )
	report "Non-FP instruction accessing FPR space"
	severity warning;
        d_out.read1_data    <= out_data_1;
        d_out.read2_data    <= out_data_2;
        d_out.read3_data    <= out_data_3;
        d_out.read1_data_hi <= out_data_1_hi;
        d_out.read2_data_hi <= out_data_2_hi;
        d_out.read3_data_hi <= out_data_3_hi;
   	

    end process register_read_0;

    -- Latch read data and ack if dbg read requested and B port not busy
    dbg_register_read: process(clk)
    begin
        if rising_edge(clk) then
            if dbg_gpr_req = '1' then
                if dbg_ack = '0' and dbg_gpr_done = '1' then
                    dbg_data <= data_2(63 downto 0);
                    dbg_ack <= '1';
                end if;
            else
                dbg_ack <= '0';
            end if;
        end if;
    end process;

    dbg_gpr_ack <= dbg_ack;
    dbg_gpr_data <= dbg_data;

    -- Dump registers if core terminates
    sim_dump_test: if SIM generate
        dump_registers: process(all)
        begin
            if sim_dump = '1' then
                loop_0: for i in 0 to 31 loop
                    report "GPR" & integer'image(i) & " " & to_hstring(registers(i));
                end loop loop_0;
                sim_dump_done <= '1';
            else
                sim_dump_done <= '0';
            end if;
        end process;
    end generate;

    -- Keep GHDL synthesis happy
    sim_dump_test_synth: if not SIM generate
        sim_dump_done <= '0';
    end generate;

    rf_log: if LOG_LENGTH > 0 generate
        signal log_data : std_ulogic_vector(71 downto 0);
    begin
        reg_log: process(clk)
        begin
            if rising_edge(clk) then
                log_data <= w_in.write_data &
                            w_in.write_enable &
                              w_in.write_reg;
            end if;
        end process;
        log_out <= log_data;
    end generate;

end architecture behaviour;
