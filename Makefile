PROGRAM_NAME=eclosion
DESTDIR ?=

ifndef DESTDIR 
	DESTDIR := /
endif

BIN_DIR=$(DESTDIR)usr/bin
LIB_DIR=$(DESTDIR)lib
DOC_DIR=$(DESTDIR)usr/share/doc

.PHONY: all

install:
	install -Dm644 README.md $(DOC_DIR)/$(PROGRAM_NAME)/README.md
	install -Dm755 eclosion.sh $(BIN_DIR)/$(PROGRAM_NAME)
	mkdir -p $(LIB_DIR)/$(PROGRAM_NAME)/{hooks,scripts,static}
	mkdir -p $(LIB_DIR)/$(PROGRAM_NAME)/scripts/init-{top,bottom}/
	install -Dm744 hooks/* $(LIB_DIR)/$(PROGRAM_NAME)/hooks/
	install -Dm744 static/* $(LIB_DIR)/$(PROGRAM_NAME)/static/
	install -Dm744 scripts/init-top/* $(LIB_DIR)/$(PROGRAM_NAME)/scripts/init-top/
	install -Dm744 scripts/init-bottom/* $(LIB_DIR)/$(PROGRAM_NAME)/scripts/init-bottom/

uninstall:
	rm -f $(BIN_DIR)/$(PROGRAM_NAME)
	rm -rf $(LIB_DIR)/$(PROGRAM_NAME)
	rm -rf $(DOC_DIR)/$(PROGRAM_NAME)
