PRIV_DIR = priv
NIF_SO = $(PRIV_DIR)/gns_nif.so

ERLANG_PATH = $(shell erl -eval 'io:format("~s", [lists:concat([code:root_dir(), "/erts-", erlang:system_info(version), "/include"])])' -s init stop -noshell)

# GameNetworkingSockets location.
# Set GNS_PATH to point to a local GameNetworkingSockets source/install tree,
# or install it system-wide so the headers are in /usr/local/include/steam/.
GNS_PATH ?=

ifneq ($(GNS_PATH),)
  GNS_CFLAGS = -I$(GNS_PATH)/include -I$(GNS_PATH)/include/steam
  GNS_LDFLAGS = -L$(GNS_PATH)/build/bin -lGameNetworkingSockets
else ifneq ($(shell pkg-config --exists GameNetworkingSockets 2>/dev/null && echo yes),)
  GNS_CFLAGS = $(shell pkg-config --cflags GameNetworkingSockets)
  GNS_LDFLAGS = $(shell pkg-config --libs GameNetworkingSockets)
else
  # Fallback: assume headers in /usr/local/include/steam and lib in default path
  GNS_CFLAGS = -I/usr/local/include -I/usr/local/include/steam
  GNS_LDFLAGS = -lGameNetworkingSockets
endif

CXX = g++
CXXFLAGS = -O2 -Wall -Wextra -Wno-unused-parameter -fPIC -shared -std=c++11 \
	-I$(ERLANG_PATH) \
	$(GNS_CFLAGS)

LDFLAGS = $(GNS_LDFLAGS)

.PHONY: all clean

all: $(NIF_SO)

$(NIF_SO): c_src/gns_nif.cpp
	@mkdir -p $(PRIV_DIR)
	$(CXX) $(CXXFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f $(NIF_SO)
