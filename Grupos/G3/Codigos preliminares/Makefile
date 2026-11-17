BOARD  = tangnano9k
FAMILY = GW1N-9C
DEVICE = GW1NR-LV9QN88PC6/I5

all: top.fs

top.json: top.v spi_master.v detector_golpe.v uart_tx.v
	yosys -p "read_verilog top.v spi_master.v detector_golpe.v uart_tx.v; synth_gowin -top top -json top.json"

top_pnr.json: top.json tangnano9k.cst
	nextpnr-himbaechel --json top.json --write top_pnr.json --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=tangnano9k.cst

top.fs: top_pnr.json
	gowin_pack -d $(FAMILY) -o top.fs top_pnr.json

prog: top.fs
	openFPGALoader -b $(BOARD) top.fs

clean:
	rm -f top.json top_pnr.json top.fs
