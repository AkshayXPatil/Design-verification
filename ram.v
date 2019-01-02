module ram (addr, idata, odata, wr, en, clk, rst);

input [3:0] idata;
input [3:0] addr;
input wr,en,clk,rst;
output reg [3:0] odata;

reg [3:0] MEM [15:0]; 

always @(posedge clk)
begin
	if (rst)
	begin
		MEM[addr] <= 4'h0;
		odata <= 4'h0;
	end
	else if(en)
	begin
		if(wr)
		begin
			MEM[addr] <= idata;
		end
		else
		begin
			odata <= MEM[addr];
		end
	end
end

endmodule