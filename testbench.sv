`include "uvm_macros.svh"
`include "interface.sv"
import uvm_pkg::*;
class seq_item extends uvm_sequence_item;

  	rand bit [3:0] addr, idata;
	rand bit wr;
	bit [3:0] odata;
	rand bit en;
	randc bit [3:0] addrc;

	`uvm_object_utils_begin(seq_item)
  		`uvm_field_int(addr, UVM_ALL_ON)
  		`uvm_field_int(wr, UVM_ALL_ON)
  		`uvm_field_int(idata, UVM_ALL_ON)
  		`uvm_field_int(en, UVM_ALL_ON)
  	`uvm_object_utils_end
  
  function new(string name = "seq_item");
    super.new(name);
  endfunction
  
 // constraint wr_rd_c { wr_en != rd_en; };
  constraint c {en > 0;} 
  
endclass

class ram_sequencer extends uvm_sequencer#(seq_item);

  `uvm_component_utils(ram_sequencer) 

  function new(string name, uvm_component parent);
    super.new(name,parent);
  endfunction
endclass

class ram_sequence extends uvm_sequence#(seq_item);
  
  `uvm_object_utils(ram_sequence)
  
  function new(string name = "mem_sequence");
    super.new(name);
  endfunction
  
  `uvm_declare_p_sequencer(ram_sequencer)
  
  virtual task body();
    seq_item item;
    repeat(20) begin
      item = seq_item::type_id::create("item");
      start_item(item);
      assert(item.randomize());
      finish_item(item);
   end 
  endtask
endclass

class ram_driver extends uvm_driver #(seq_item);

  virtual ram_intf vintf;
  `uvm_component_utils(ram_driver)
  logic [3:0] addr;
  function new (string name, uvm_component parent);
    super.new(name, parent);
    addr = 4'h0;
  endfunction 
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual ram_intf)::get(this, "", "vintf", vintf))
       `uvm_fatal("NO_VIF",{"virtual interface must be set for: ",get_full_name(),".vintf"});
  endfunction: build_phase

  virtual task run_phase(uvm_phase phase);
    reset();
    forever begin
      seq_item item;
      seq_item_port.get_next_item(item);
      drive(item);
      seq_item_port.item_done();
    end
  endtask
  
  virtual task reset();
    wait(vintf.D.rst)
		$display("----------Reset Started---------");
		vintf.D.addr  <= 0; 
		vintf.D.idata <= 0;
		vintf.D.wr	<= 0; 	
		vintf.D.en	<= 0;
    
		do 
		begin
          @(posedge vintf.D.clk);
			vintf.D.addr = addr;
          	addr = addr+1'b1;
          $display("ADDR: %0h at %0t",addr, $time);
		end
        while(vintf.D.rst);
    
		$display("----------Reset Done----------");
  endtask
    
  virtual task drive(seq_item item);
	
		vintf.en <= 0;
		vintf.wr <= 0;
    
    	
		@(posedge vintf.D.clk);
		
		vintf.D.addr	<= item.addr;
		vintf.D.idata	<= item.idata;
		vintf.D.wr		<= item.wr;
		vintf.D.en		<= item.en;
    if(!item.wr)
		begin
			item.odata = vintf.D.odata;
		end
	endtask
endclass 


class ram_monitor extends uvm_monitor;

  virtual ram_intf vintf;

  uvm_analysis_port #(seq_item) item_collected_port;
  
  seq_item trans_collected;

  `uvm_component_utils(ram_monitor)

  function new (string name, uvm_component parent);
    super.new(name, parent);
    trans_collected = new();
    item_collected_port = new("item_collected_port", this);
  endfunction 

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual ram_intf)::get(this, "", "vintf", vintf))
       `uvm_fatal("NOVIF",{"virtual interface must be set for: ",get_full_name(),".vintf"});
  endfunction
  
  virtual task run_phase(uvm_phase phase);
      forever begin
        @(posedge vintf.M.clk);
        wait(vintf.M.en);
			trans_collected.addr	= vintf.M.addr;
			trans_collected.idata	= vintf.M.idata;
			trans_collected.wr		= vintf.M.wr;
			trans_collected.en		= vintf.M.en;
			
			if(!vintf.M.wr)
			begin
				trans_collected.odata = vintf.D.odata;
			end
			item_collected_port.write(trans_collected);
		end
	endtask
endclass 


class ram_agent extends uvm_agent;

  ram_driver    driver;
  ram_sequencer sequencer;
  ram_monitor   monitor;

  `uvm_component_utils(ram_agent)
  
  function new (string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    monitor = ram_monitor::type_id::create("monitor", this);

    if(get_is_active() == UVM_ACTIVE) begin
      driver    = ram_driver::type_id::create("driver", this);
      sequencer = ram_sequencer::type_id::create("sequencer", this);
    end
  endfunction
  
  function void connect_phase(uvm_phase	 phase);
    if(get_is_active() == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction 
endclass


class ram_scoreboard extends uvm_scoreboard;
  
  seq_item pkt_qu[$];
  
  bit [3:0] sc_mem [16];

  uvm_analysis_imp#(seq_item, ram_scoreboard) item_collected_export;
  `uvm_component_utils(ram_scoreboard)

  function new (string name, uvm_component parent);
    super.new(name, parent);
  endfunction 
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
      item_collected_export = new("item_collected_export", this);
    foreach(sc_mem[i]) sc_mem[i] = 4'h0;
  endfunction: build_phase
  
  virtual function void write(seq_item pkt);
    pkt_qu.push_back(pkt);
  endfunction : write

	virtual task run_phase(uvm_phase phase);
		seq_item mem_pkt;
      
		forever begin
          wait(pkt_qu.size() > 0 );
			mem_pkt = pkt_qu.pop_front();
			if(mem_pkt.en)
			begin
				if(mem_pkt.wr)
				begin
                  `uvm_info(get_type_name(), $sformatf("-----------start write------------"), UVM_LOW);
              	  `uvm_info(get_type_name(), $sformatf("ADDR: %0h", mem_pkt.addr), UVM_LOW);
                  `uvm_info(get_type_name(), $sformatf("IDATA: %0h", mem_pkt.idata), UVM_LOW);
                  sc_mem[mem_pkt.addr] = mem_pkt.idata;
				end
				else
				begin
                  `uvm_info(get_type_name(), $sformatf("-----------start read------------"), UVM_LOW);
              	    `uvm_info(get_type_name(), $sformatf("ADDR: %0h", mem_pkt.addr), UVM_LOW);
					if(sc_mem[mem_pkt.addr] == mem_pkt.odata)
					begin
                      `uvm_info(get_type_name(), $sformatf("EXP. DATA: %0h ACT. DATA: %0h  MATCHED!!", sc_mem[mem_pkt.addr], mem_pkt.odata), UVM_LOW);
					end
					else 
					begin
                      `uvm_info(get_type_name(), $sformatf("EXP. DATA: %0h ACT. DATA: %0h  ERROR!!", sc_mem[mem_pkt.addr], mem_pkt.odata), UVM_LOW);
						`uvm_error(get_type_name(),"***ERROR***");
					end
				end
			end
		end
	endtask
endclass


class ram_environment extends uvm_env;
  
  ram_agent      agnt;
  ram_scoreboard scb;
  
  `uvm_component_utils(ram_environment)
  
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction 

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agnt = ram_agent::type_id::create("agnt", this);
    scb  = ram_scoreboard::type_id::create("scb", this);
  endfunction 
  
  function void connect_phase(uvm_phase phase);
    agnt.monitor.item_collected_port.connect(scb.item_collected_export);
  endfunction 
endclass 


class ram_base_test extends uvm_test;

  `uvm_component_utils(ram_base_test)
   
  ram_environment env;
  ram_sequence seq;
  
  function new(string name = "ram_base_test",uvm_component parent=null);
    super.new(name,parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
	seq = ram_sequence::type_id::create("seq");
    env = ram_environment::type_id::create("env", this);
  endfunction : build_phase
  
  virtual function void end_of_elaboration();
    print();
  endfunction
 
 function void report_phase(uvm_phase phase);
   uvm_report_server svr;
   super.report_phase(phase);
   
   svr = uvm_report_server::get_server();
   if(svr.get_severity_count(UVM_FATAL)+svr.get_severity_count(UVM_ERROR)>0) begin
     `uvm_info(get_type_name(), "---------------------------------------", UVM_NONE)
     `uvm_info(get_type_name(), "----            TEST FAIL          ----", UVM_NONE)
     `uvm_info(get_type_name(), "---------------------------------------", UVM_NONE)
    end
    else begin
     `uvm_info(get_type_name(), "---------------------------------------", UVM_NONE)
     `uvm_info(get_type_name(), "----           TEST PASS           ----", UVM_NONE)
     `uvm_info(get_type_name(), "---------------------------------------", UVM_NONE)
    end
  endfunction 
  
  task run_phase(uvm_phase phase);
    
    phase.raise_objection(this);
      seq.start(env.agnt.sequencer);
    phase.drop_objection(this);
    
    //set a drain-time for the environment if desired
    phase.phase_done.set_drain_time(this, 50);
  endtask 

endclass


module tbench_top;

  bit clk;
  bit rst;
  
  always #0.5 clk = ~clk;
  
  initial begin
    rst = 0;
    //#33 rst =0;
  end 
  ram_intf intf(clk,rst);
  
  ram uut (.addr(intf.addr), .idata(intf.idata), .odata(intf.odata), .wr(intf.wr), .en(intf.en), .clk(intf.clk), .rst(intf.rst));
  
  initial begin 
    uvm_config_db#(virtual ram_intf)::set(uvm_root::get(),"*","vintf",intf);
  end
  
  initial begin 
    run_test();
  end
  
endmodule