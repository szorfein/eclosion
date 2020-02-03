PROGRAM_NAME=eclosion
DESTDIR ?=

ifndef DESTDIR 
	DESTDIR := /
endif

BIN_DIR=$(DESTDIR)usr/bin
LIB_DIR=$(DESTDIR)lib
DOC_DIR=$(DESTDIR)usr/share/doc
CONF_DIR=$(DESTDIR)etc

.PHONY: _all
_all:

install:
	install -Dm644 README.md $(DOC_DIR)/$(PROGRAM_NAME)/README.md
	install -Dm644 docs/* $(DOC_DIR)/$(PROGRAM_NAME)/
	install -Dm755 eclosion.sh $(BIN_DIR)/$(PROGRAM_NAME)
	mkdir -p $(LIB_DIR)/$(PROGRAM_NAME)/{hooks,scripts,static}
	mkdir -p $(LIB_DIR)/$(PROGRAM_NAME)/scripts/init-{top,bottom}/
	install -Dm744 hooks/* $(LIB_DIR)/$(PROGRAM_NAME)/hooks/
	install -Dm744 scripts/init-top/* $(LIB_DIR)/$(PROGRAM_NAME)/scripts/init-top/
	install -Dm744 scripts/init-bottom/* $(LIB_DIR)/$(PROGRAM_NAME)/scripts/init-bottom/
	mkdir -p $(CONF_DIR)/$(PROGRAM_NAME)
	install -Dm755 eclosion-gen-conf.sh $(BIN_DIR)/$(PROGRAM_NAME)-gen-conf

uninstall:
	rm -f $(BIN_DIR)/$(PROGRAM_NAME)
	rm -f $(BIN_DIR)/$(PROGRAM_NAME)-gen-conf.sh
	rm -rf $(LIB_DIR)/$(PROGRAM_NAME)
	rm -rf $(DOC_DIR)/$(PROGRAM_NAME)
	rm -rf $(CONF_DIR)/$(PROGRAM_NAME)
