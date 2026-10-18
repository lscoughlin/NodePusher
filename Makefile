# NodePusher build. The Lazarus package (NodePusher.lpk) and test project
# (tests/NodePusherTests.lpi) list the same units. Keep them in parity.

FPC      ?= fpc
BUILD    ?= build
FPCFLAGS ?= -Mobjfpc -Sh -vewn
CHECKS   ?= -Cr -Co -Ct -Ci -gh -gl

SRC_UNITS = \
  src/Pusher.Types.pas \
  src/Pusher.State.pas \
  src/Pusher.Emitter.pas \
  src/Pusher.Emitter.Json.pas \
  src/Pusher.Emitter.Yaml.pas \
  src/Pusher.Sinks.pas \
  src/Pusher.pas

TEST_UNITS = \
  tests/TestPusherCore.pas \
  tests/TestJson.pas \
  tests/TestYaml.pas \
  tests/TestSinks.pas

.PHONY: all test clean

all: $(BUILD)/lib/Pusher.ppu

$(BUILD)/lib/Pusher.ppu: $(SRC_UNITS)
	mkdir -p $(BUILD)/lib
	$(FPC) $(FPCFLAGS) -FU$(BUILD)/lib -Fusrc src/Pusher.pas

$(BUILD)/NodePusherTests: $(SRC_UNITS) $(TEST_UNITS) tests/NodePusherTests.lpr
	mkdir -p $(BUILD)/tests
	$(FPC) $(FPCFLAGS) $(CHECKS) -FU$(BUILD)/tests -FE$(BUILD) -Fusrc -Futests tests/NodePusherTests.lpr

test: $(BUILD)/NodePusherTests
	$(BUILD)/NodePusherTests --all --format=plain

clean:
	rm -rf $(BUILD)
