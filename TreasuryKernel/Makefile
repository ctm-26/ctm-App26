CC      ?= gcc
CFLAGS  ?= -std=c11 -O2 -Wall -Wextra -Wpedantic -Wshadow -Wstrict-prototypes \
           -Wmissing-prototypes -Wno-unused-parameter -D_POSIX_C_SOURCE=200809L
LDLIBS  := -lsqlite3

SRC_DIR := src
BIN     := treasury

SRCS := \
	$(SRC_DIR)/treasury.c \
	$(SRC_DIR)/db.c \
	$(SRC_DIR)/util.c \
	$(SRC_DIR)/csv.c \
	$(SRC_DIR)/account.c \
	$(SRC_DIR)/category.c \
	$(SRC_DIR)/rule.c \
	$(SRC_DIR)/import.c \
	$(SRC_DIR)/tx.c \
	$(SRC_DIR)/report.c \
	$(SRC_DIR)/audit.c

OBJS := $(SRCS:.c=.o)

.PHONY: all clean test debug

all: $(BIN)

$(BIN): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDLIBS)

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

debug: CFLAGS += -O0 -g3 -fsanitize=address,undefined
debug: LDLIBS += -fsanitize=address,undefined
debug: clean all

test: $(BIN)
	@bash tests/run_tests.sh

clean:
	rm -f $(OBJS) $(BIN)
