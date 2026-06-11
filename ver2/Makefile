COMPONENT=WSNAppC
TINYOS_ROOT_DIR?=$(TOSROOT)

CFLAGS += -I$(TINYOS_ROOT_DIR)/tos/lib/ftsp
CFLAGS += -I$(TINYOS_ROOT_DIR)/tos/lib/ftsp/cc2420
CFLAGS += -I$(TINYOS_ROOT_DIR)/tos/lib/net
CFLAGS += -I$(TINYOS_ROOT_DIR)/tos/lib/net/le
CFLAGS += -I$(TINYOS_ROOT_DIR)/tos/lib/net/ctp
CFLAGS += -I$(TINYOS_ROOT_DIR)/tos/lib/net/drip

CFLAGS += -DTOSH_DATA_LENGTH=60

include $(TINYOS_ROOT_DIR)/Makefile.include