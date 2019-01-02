`timescale 1ns / 1ps

class transaction;

rand logic [3:0] addr, idata;
rand logic wr;
logic [3:0] odata;
logic en;
 function new();
	en = 1'b1;
 endfunction
endclass

class generator;
	mailbox mb;
	event done;
	int rpt_cnt;
	int cnt;
	function new(mailbox mb, event done);
		this.mb = mb;
		this.done = done;
	endfunction

	task main();
		repeat(rpt_cnt)
		begin
			transaction trans = new();
			if(!trans.randomize())
			begin
				$fatal("conflict");
			end
			else
			begin
				$display("--------generated transaction: %0d-------------",cnt);
				$display ("en: %b", trans.en);
				$display("addr: %h", trans.addr);
				$display("wr: %b", trans.wr);
				if(trans.wr)
				begin
					$display("idata: %h", trans.idata);
				end
				mb.put(trans);
			end
			cnt++;
		end
		-> done;
	endtask
endclass

class driver;
	mailbox mb;
	virtual ram_intf vintf;
	int tran_cnt;
	logic [3:0] addr;
	
	function new(mailbox mb, virtual ram_intf vintf);
		this.vintf = vintf;
		this.mb = mb;
		addr = 4'h0;
	endfunction
	
	task reset;
		wait(vintf.rst);
		$display("----------Reset Started---------");
		vintf.addr  <= 0; 
		vintf.idata <= 0;
		vintf.wr	<= 0; 	
		vintf.en	<= 0;
		do 
		begin
			@(posedge vintf.clk);
			vintf.addr = addr;
			addr = addr+1'b1;
		end
		while(vintf.rst);
		$display("----------Reset Done----------");
	endtask
	
	task drive;
		transaction trans;
		@(negedge vintf.clk);
		mb.get(trans);
		vintf.addr  <= trans.addr;  
		vintf.idata <= trans.idata; 
		vintf.wr 	<= trans.wr; 	
		vintf.en	<= trans.en;
		@(posedge vintf.clk);
		$display("------------driven transaction: %0d--------------", tran_cnt);
		$display ("en: %b", trans.en);
		$display("addr: %h", trans.addr);
		$display("wr: %b", trans.wr);
		if(!trans.wr)
		begin
			trans.odata = vintf.odata;
			$display("odata: %h", trans.odata);
		end
		else
		begin
			$display("idata: %h", trans.idata);
		end
		tran_cnt++;
	endtask
	
	task main();
		forever begin 
			drive();
		end
	endtask
endclass

class environment;
	generator gen;
	driver driv;
	mailbox mb;
	virtual ram_intf vintf;
	event gen_done;
	
	function new(virtual ram_intf vintf);
		this.vintf = vintf;
		mb = new();
		gen = new(mb, gen_done);
		driv = new(mb, vintf);
	endfunction
	
	task pre_test();
		driv.reset();
	endtask
	
	task test();
		fork
			gen.main();
			driv.main();
		join_any
	endtask
	
	task post_test();
		wait(gen_done.triggered);
		wait(gen.rpt_cnt == driv.tran_cnt);
	endtask
	
	task run();
		pre_test();
		test();
		post_test();
		$finish;
	endtask
endclass

program test(ram_intf intf);
	environment env;
	initial begin
		env = new(intf);
		env.gen.rpt_cnt = 20;
		env.run();
	end
endprogram

module ram_test;
	bit clk,rst;
	
	always #0.5 clk = ~clk;
	
	initial begin
	rst = 1;
	#17                               
	rst = 0;
	end
	ram_intf intf(clk,rst);
	test t1(intf);
	ram uut (.addr(intf.addr), .idata(intf.idata), .odata(intf.odata), .wr(intf.wr), .en(intf.en), .clk(intf.clk), .rst(intf.rst));
endmodule