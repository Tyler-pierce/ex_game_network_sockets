PRIV_DIR = priv
NIF_SO = $(PRIV_DIR)/gns_nif.so

ERLANG_PATH = $(shell erl -eval 'io:format("~s", [lists:concat([code:root_dir(), "/erts-", erlang:system_info(version), "/include"])])' -s init stop -noshell)
ERL_INTERFACE_INCLUDE = $(shell erl -eval 'io:format("~s", [code:lib_dir(erl_interface, include)])' -s init stop -noshell)
ERL_INTERFACE_LIB = $(shell erl -eval 'io:format("~s", [code:lib_dir(erl_interface, lib)])' -s init stop -noshell)

GNS_INCLUDE = $(shell pwd)/../GameNetworkingSockets/include

CXX = g++
CXXFLAGS = -O2 -Wall -Wextra -Wno-unused-parameter -fPIC -shared -std=c++11 \
	-I$(ERLANG_PATH) \
	-I$(GNS_INCLUDE) \
	-I$(GNS_INCLUDE)/steam

LDFLAGS = -lGameNetworkingSockets

.PHONY: all clean

all: $(NIF_SO)

$(NIF_SO): c_src/gns_nif.cpp
	@mkdir -p $(PRIV_DIR)
	$(CXX) $(CXXFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f $(NIF_SO)
