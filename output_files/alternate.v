module zuckberberg (
			output wire [3:0] rowwrite,
			input [3:0] colread,
			input clk,
			output wire [3:0] grounds,
			output wire [6:0] display,
			input pushbutton //may be used as clock
			);
 
 
reg [15:0] data_all;
wire [3:0] keyout;
reg [25:0] clk1;
reg [1:0] ready_buffer;
reg ack;
reg statusordata;


// slow down clock in cpu
always @(posedge clk)
    clk1<=clk1+1;


 
//memory map is defined here
localparam	BEGINMEM=12'h000,
		ENDMEM=12'h1ff,
		KEYPAD=12'h900,
		SEVENSEG=12'hb00;
		
		
//  memory chip
reg [15:0] memory [0:127]; 
 
// cpu's input-output pins
wire [15:0] data_out;
reg [15:0] data_in;
wire [11:0] address;
wire memwt;


sevensegment ss1 (.datain(data_all), .grounds(grounds), .display(display), .clk(clk));
 
keypad  kp1(.rowwrite(rowwrite), .colread(colread), .clk(clk), .ack(ack), .statusordata(statusordata), .keyout(keyout));
 
bird br1 (.clk(clk1[15]), .data_in(data_in), .data_out(data_out), .address(address), .memwt(memwt));
 
 
//multiplexer for cpu input
always @*
	if ( (BEGINMEM<=address) && (address<=ENDMEM) )
		begin
			data_in=memory[address];
			ack=0;
			statusordata=0;
		end
	else if (address==KEYPAD+1)
		begin	
			statusordata=1;
			data_in=keyout;
			ack=0;
		end
	else if (address==KEYPAD)
		begin
			statusordata=0;
			data_in=keyout;
			ack=1;
		end
	else
		begin
			data_in=16'hf345; //any number
			ack=0;
			statusordata=0;
		end
 
//multiplexer for cpu output 
 
always @(posedge clk) //data output port of the cpu
	if (memwt)
		if ( (BEGINMEM<=address) && (address<=ENDMEM) )
			memory[address]<=data_out;
		else if ( SEVENSEG==address) 
			data_all<=data_out;
 
 // toplama data_out da
initial 
	begin
		data_all=0;
		ack=0;
		statusordata=0;
		$readmemh("ram.dat", memory);
	end
 
endmodule


//bird CPU
module bird (
		input clk,
		input [15:0] data_in,
		output reg [15:0] data_out,
		output reg [11:0] address,
		output memwt,
		output [15:0] reg0
		);
 
reg [11:0] pc, ir; //program counter, instruction register
 
reg [4:0] state; //FSM
reg [15:0] regbank [7:0];//registers 
reg zeroflag; //zero flag register
reg [15:0] result; //output for result
 
 
localparam	FETCH=4'b0000,
		LDI=4'b0001, 
		LD=4'b0010,
		ST=4'b0011,
		JZ=4'b0100,
		JMP=4'b0101,
		ALU=4'b0111,
		PUSH=4'b1000,
		POP1=4'b1001,
		POP2=4'b1100,
		CALL=4'b1010,
		RET1=4'b1011,
		RET2=4'b1101;
 
 
wire zeroresult; 
 
always @(posedge clk)
	case(state) 
		FETCH: 
			begin
				if ( data_in[15:12]==JZ) // if instruction is jz  
					if (zeroflag)  //and if last bit of 7th register is 0 then jump to jump instruction state
						state <= JMP;
					else
						state <= FETCH; //stay here to catch next instruction
			else
				state <= data_in[15:12]; //read instruction opcode and jump the state of the instruction to be read
				ir<=data_in[11:0]; //read instruction details into instruction register
				pc<=pc+1; //increment program counter
			end
 
		LDI:
			begin
				regbank[ ir[2:0] ] <= data_in; //if inst is LDI get the destination register number from ir and move the data in it.
				pc<=pc+1; //for next instruction (32 bit instruction)  
				state <= FETCH;
			end
 
		LD:
			begin
				regbank[ir[2:0]] <= data_in;
				state <= FETCH;  
				end 
 
		ST:
			begin
				state <= FETCH;  
			end
 
		JMP:
			begin
				pc <= pc+ir;
				state <= FETCH;  
			end
 
		ALU:
			begin
				regbank[ir[2:0]]<=result;
				zeroflag<=zeroresult;
				state <= FETCH;
			end
 
		PUSH:
			begin
				 regbank[7]<=regbank[7]-1;
				 state <= FETCH;
			end
 
		POP1:
			begin
				regbank[7]<=regbank[7]+1;
				state<=POP2;
			end
 
		POP2: 
			begin
				regbank[ir[2:0]] <= data_in;
				state<=FETCH;
			end
 
		CALL: 
			begin
				regbank[7]<=regbank[7]-1;
				pc<=pc+ir;
				state<=FETCH;
			end
 
		RET1:
			begin
				regbank[7]<=regbank[7]-1;
				state<=RET2;
			end
 
		RET2:
			begin
				pc<=data_in;
				state<=FETCH; 
			end
 
	endcase
 
always @*
	case (state)
		LD:	address=regbank[ir[5:3]][11:0];
		ST:	address=regbank[ir[5:3]][11:0];
		PUSH:	address=regbank[7];
		POP2:	address=regbank[7][11:0];
		CALL:	address=regbank[7][11:0];
		RET2:	address=regbank[7][11:0];
		default: address=pc;
	endcase
 
 
assign memwt=(state==ST) || (state==PUSH) || (state==CALL); 
 
always @*
	case (state)
		CALL: data_out = pc;
		default: data_out = regbank[ir[8:6]];
	endcase
 
always @* //ALU Operation
	case (ir[11:9])
		3'h0: result = regbank[ir[8:6]]+regbank[ir[5:3]]; //000
		3'h1: result = regbank[ir[8:6]]-regbank[ir[5:3]]; //001
		3'h2: result = regbank[ir[8:6]]&regbank[ir[5:3]]; //010
		3'h3: result = regbank[ir[8:6]]|regbank[ir[5:3]]; //011
		3'h4: result = regbank[ir[8:6]]^regbank[ir[5:3]]; //100
		3'h7: case (ir[8:6])
			3'h0: result = !regbank[ir[5:3]];
			3'h1: result = regbank[ir[5:3]];
			3'h2: result = regbank[ir[5:3]]+1;
			3'h3: result = regbank[ir[5:3]]-1;
			default: result=16'h0000;
		     endcase
		default: result=16'h0000;
	endcase
 
assign zeroresult = ~|result;
 
initial begin;
	state=FETCH;
	zeroflag=0;
	pc=0;
end
 
endmodule


module sevensegment(datain, grounds, display, clk);
 
	input wire [15:0] datain;
	output reg [3:0] grounds;
	output reg [6:0] display;
	input clk;
	
	reg [3:0] data [3:0];
	reg [1:0] count;
	reg [25:0] clk1;
	
	always @(posedge clk1[15])
		begin
			grounds <= {grounds[2:0],grounds[3]};
			count <= count + 1;
		end
	
	always @(posedge clk)
		clk1 <= clk1 + 1;
	
	always @(*)
		case(data[count])	
			0:display=7'b1111110; //starts with a, ends with g
			1:display=7'b0110000;
			2:display=7'b1101101;
			3:display=7'b1111001;
			4:display=7'b0110011;
			5:display=7'b1011011;
			6:display=7'b1011111;
			7:display=7'b1110000;
			8:display=7'b1111111;
			9:display=7'b1111011;
			'ha:display=7'b1110111;
			'hb:display=7'b0011111;
			'hc:display=7'b1001110;
			'hd:display=7'b0111101;
			'he:display=7'b1001111;
			'hf:display=7'b1000111;
			default display=7'b1111111;
		endcase
	
	always @*
		begin
			data[0] = datain[15:12];
			data[1] = datain[11:8];
			data[2] = datain[7:4];
			data[3] = datain[3:0];
		end
	
	initial begin		
		count = 2'b0;
		grounds = 4'b1110;
		clk1 = 0;
	end
endmodule

module keypad (
						output reg [3:0] rowwrite,
						input [3:0] colread,
						input clk,
						input ack,
						input statusordata,
						output reg [15:0] keyout
						);
wire keypressed;		
reg [25:0] clk1;
reg ready;
reg [3:0] keyread, data;
reg [3:0] rowpressed;
reg [3:0] pressedcol [0:3];
reg [11:0] rowpressed_buffer0, rowpressed_buffer1, rowpressed_buffer2, rowpressed_buffer3;
reg [3:0] rowpressed_debounced;

always @(posedge clk)
	clk1<=clk1+1;

always @(posedge clk1[15])
	rowwrite<={rowwrite[2:0], rowwrite[3]};

always @(posedge clk1[15])
	if (rowwrite== 4'b1110)
		begin
			rowpressed[0]<= ~(&colread); //colread=1111--> none of them pressed, colread=1110 --> 1, colread=1101-->2, 1011-->3, 0111->A
			pressedcol[0]<=colread;
		end
	else if (rowwrite==4'b1101)
		begin
			rowpressed[1]<= ~(&colread); //colread=1111--> none of them pressed, colread=1110 --> 4, colread=1101-->5, 1011-->6, 0111->B
			pressedcol[1]<=colread;
		end
	else if (rowwrite==4'b1011)
		begin
			rowpressed[2]<= ~(&colread); //colread=1111--> none of them pressed, colread=1110 --> 7, colread=1101-->8, 1011-->9, 0111->C
			pressedcol[2]<=colread;
		end
	else if (rowwrite==4'b0111)
		begin
			rowpressed[3]<= ~(&colread); //colread=1111--> none of them pressed, colread=1110 --> *(E), colread=1101-->0, 1011-->#(F), 0111->D
			pressedcol[3]<=colread;
		end
		
wire transition0_10;
wire transition0_01;

assign transition0_10=~|rowpressed_buffer0;
assign transition0_01=&rowpressed_buffer0;

wire transition1_10;
wire transition1_01;

assign transition1_10=~|rowpressed_buffer1;
assign transition1_01=&rowpressed_buffer1;

wire transition2_10;
wire transition2_01;

assign transition2_10=~|rowpressed_buffer2;
assign transition2_01=&rowpressed_buffer2;

wire transition3_10;
wire transition3_01;

assign transition3_10=~|rowpressed_buffer3; //kpd=1-->0
assign transition3_01=&rowpressed_buffer3;  //kpd=0-->1


always @(posedge clk1[15])
	begin
		rowpressed_buffer0<= {rowpressed_buffer0[10:0],rowpressed[0]};
		if (rowpressed_debounced[0]==0 && transition0_01)
			rowpressed_debounced[0]<=1;
		if (rowpressed_debounced[0]==1 && transition0_10)
			rowpressed_debounced[0]<=0;
	
	rowpressed_buffer1<= {rowpressed_buffer1[10:0],rowpressed[1]};
		if (rowpressed_debounced[1]==0 && transition1_01)
			rowpressed_debounced[1]<=1;
		if (rowpressed_debounced[1]==1 && transition1_10)
			rowpressed_debounced[1]<=0;
			
	rowpressed_buffer2<= {rowpressed_buffer2[10:0],rowpressed[2]};
		if (rowpressed_debounced[2]==0 && transition2_01)
			rowpressed_debounced[2]<=1;
		if (rowpressed_debounced[2]==1 && transition2_10)
			rowpressed_debounced[2]<=0;
	
	rowpressed_buffer3<= {rowpressed_buffer3[10:0],rowpressed[3]};
		if (rowpressed_debounced[3]==0 && transition3_01)
			rowpressed_debounced[3]<=1;
		if (rowpressed_debounced[3]==1 && transition3_10)
			rowpressed_debounced[3]<=0;
	end 

always @*
	begin
		if (rowpressed_debounced[0]==1)
			begin
				if (pressedcol[0]==4'b1110)
					keyread=4'h1;
				else if (pressedcol[0]==4'b1101)
					keyread=4'h2;
				else if (pressedcol[0]==4'b1011)
					keyread=4'h3;
				else if (pressedcol[0]==4'b0111)
					keyread=4'hA;
				else keyread=4'b0000;
			end
		else if (rowpressed_debounced[1]==1)
			begin
				if (pressedcol[1]==4'b1110)
					keyread=4'h4;
				else if (pressedcol[1]==4'b1101)
					keyread=4'h5;
				else if (pressedcol[1]==4'b1011)
					keyread=4'h6;
				else if (pressedcol[1]==4'b0111)
					keyread=4'hB;
				else keyread=4'b0000;
			end
		else if (rowpressed_debounced[2]==1)
			begin
				if (pressedcol[2]==4'b1110)
					keyread=4'h7;
				else if (pressedcol[2]==4'b1101)
					keyread=4'h8;
				else if (pressedcol[2]==4'b1011)
					keyread=4'h9;
				else if (pressedcol[2]==4'b0111)
					keyread=4'hC;
				else keyread=4'b0000;
			end
		else if (rowpressed_debounced[3]==1)
			begin
				if (pressedcol[3]==4'b1110)
					keyread=4'hE;
				else if (pressedcol[3]==4'b1101)
					keyread=4'h0;
				else if (pressedcol[3]==4'b1011)
					keyread=4'hF;
				else if (pressedcol[3]==4'b0111)
					keyread=4'hD;
				else keyread=4'b0000;
			end
		else keyread=4'b0000;
	end //always


assign keypressed= rowpressed_debounced[0]||rowpressed_debounced[1]||rowpressed_debounced[2]||rowpressed_debounced[3];

reg [1:0] keypressed_buffer; //yeni karakter için parmağı çekip tekrar basmamız için gerekli

always @(posedge clk)
	keypressed_buffer<={keypressed_buffer[0],keypressed};

always @(posedge clk)
	if ((keypressed_buffer==2'b01)&&(ready==0))
		begin
			data<=keyread;
			ready<=1;
		end
	else if ((ack==1)&&(ready==1))
		ready<=0;
	
always @(*)
	if (statusordata==1)
		keyout={15'b0,ready};
	else
		keyout={12'b0,data};
	
initial 
	begin
		rowwrite=4'b1110;		
		ready=0;
	end
endmodule




