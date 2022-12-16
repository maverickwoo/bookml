# BookML: bookdown flavoured GitBook port for LaTeXML
# Copyright (C) 2021  Vincenzo Mantova <v.l.mantova@leeds.ac.uk>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

### UTILS
# recursive wildcard (https://stackoverflow.com/a/18258352)
override rwildcard = $(foreach d,$(wildcard $(1:=/*)),$(call rwildcard,$d,$2) $(filter $(subst *,%,$2),$d))
# backward compatible file/grep function
ifeq ($(findstring version-3.8,version-$(MAKE_VERSION)),version-3.8)
  ifeq ($(OS),Windows_NT)
    override bfile = $(shell type $(1))
  else
    override bfile = $(shell cat -- $(1))
  endif
else
  override bfile = $(file < $(1))
endif
override grep  = $(findstring $(1),$(call bfile,$(2)))

### CONFIGURATION
# Configure these variables inside 'Makefile' before 'include bookml/bookml.mk'
# where to store auxiliary files (*.aux, *.d, ...)
AUX_DIR  ?= auxdir
DEPS_DIR ?= $(AUX_DIR)/deps
# latexmk command and options
LATEXMK      ?= latexmk
LATEKMKFLAGS ?=
# latexml commands and options
LATEXML          ?= latexml
LATEXMLPOST      ?= latexmlpost
LATEXMLFLAGS     ?=
LATEXMLPOSTFLAGS ?= --urlstyle=file --pmml --mathtex --navigationtoc=context
# how to split into multiple files (section, chapter, etc). Set to empty string to disable splitting.
SPLITAT ?= section
# source files: by default, all .tex files containing a \documentclass
ifndef SOURCES
  SOURCES := $(foreach f,$(wildcard *.tex),$(if $(call grep,\documentclass,$(f)),$(f)))
endif
# files to be built: by default, a .zip file for each .tex file in $(SOURCES)
TARGETS ?= $(SOURCES:.tex=.zip)
# various terminal commands: by default, use typical Windows or Unix version
ifeq ($(OS),Windows_NT)
  RMDIR       =  rd /s /q
  RM          =  del /f /s /q
  MKDIR       =  mkdir
  sep         := $(strip \)
else
  RMDIR       =  rm -fr --
  RM          =  rm -f --
  MKDIR       =  mkdir -p --
  sep         =  /
endif
ZIP           ?= zip
ZIP_EXCLUDE   ?= -x

### INTERNAL VARIABLES
LATEXMK_INTFLAGS = -norc -interaction=nonstopmode -halt-on-error -recorder -deps -deps-out="$(DEPS_DIR)/$@.d" -aux-directory="$(AUX_DIR)" -emulate-aux-dir
BOOKML_DEPS_HTML = $(wildcard LaTeXML-html5.xsl bookml/XSLT/*.xsl bookml/*.rng bookml/CSS/*.css bookml/gitbook/css/fontawesome/*.ttf bookml/gitbook/css/*.css bookml/js/*.js bmluser/*.css)
BOOKML_DEPS_XML  = $(wildcard bookml/*.ltxml bookml/*.rng)

# Do not delete intermediate files
.SECONDARY:

# Enable second expansion for $$(...) dependencies
.SECONDEXPANSION:

# Delete files on error
.DELETE_ON_ERROR:

.PHONY: all clean clean-aux clean-html clean-pdf clean-xml clean-zip debug debug-targets debug-latexml debug-dvisvgm debug-latexmk debug-preview debug-zip

all: $(TARGETS)

clean: clean-aux clean-html clean-pdf clean-xml clean-zip

clean-aux:
	-$(RM) $(foreach ext,.log .latexml.log .latexmlpost.log .fls $(sep)LaTeXML.cache,$(TARGETS:.zip=$(ext)))
	-$(RMDIR) $(subst /,$(sep),$(DEPS_DIR) $(AUX_DIR))
clean-html:
	-$(RMDIR) $(TARGETS:.zip=)
clean-pdf:
	-$(RM) $(TARGETS:.zip=.pdf)
clean-xml:
	-$(RM) $(TARGETS:.zip=.xml)
	-$(RMDIR) $(patsubst %.zip,bmlimages/%,$(TARGETS)) $(patsubst %.zip,bmlimages/%-*.svg,$(TARGETS))
clean-zip:
	-$(RM) $(TARGETS)

debug: debug-targets debug-latexml debug-dvisvgm debug-latexmk debug-preview debug-zip
	@echo "=================================="
	@echo "BookML: everything seems to be ok."
debug-targets:
	@echo "Main TeX files: $(if $(TARGETS),$(TARGETS:.zip=.tex),no .tex files with \documentclass found in this directory)."
debug-latexml:
	@echo "LaTeXML version: $(shell $(LATEXML) --VERSION 2>&1)."
debug-dvisvgm:
	@echo "dvisvgm version: $(shell dvisvgm --version)."
debug-latexmk:
	@echo "latexmk version: $(shell $(LATEXMK) --version)."
debug-preview:
	@echo "preview.sty location: $(if $(shell kpsewhich preview.sty),$(shell kpsewhich preview.sty),$(error preview.sty: No such file or directory))."
debug-zip:
	@echo "Executing ZIP:"
	@zip -v


-include $(wildcard $(DEPS_DIR)/*.d)

$(DEPS_DIR):
	$(MKDIR) $(subst /,$(sep),$@)

%.pdf: %.tex | $(DEPS_DIR)
	$(LATEXMK) $(LATEKMKFLAGS) $(LATEXMK_INTFLAGS) -g -pdf -dvi- -ps- $<

%.xml: %.tex $(BOOKML_DEPS_XML) | %.pdf
	$(LATEXML) $(if $(call grep,{bookml/bookml},$<),,--preamble=literal:\\RequirePackage{bookml/bookml}) $(LATEXMLFLAGS) --destination=$@ $<

%/index.html: %.xml %.pdf $(BOOKML_DEPS_HTML) $$(wildcard bmlimages/$$**.svg)
	$(LATEXMLPOST) $(if $(wildcard LaTeXML-html5.xsl),,--stylesheet=bookml/XSLT/bookml-html5.xsl) $(if $(SPLITAT),--splitat=$(SPLITAT)) $(LATEXMLPOSTFLAGS) --destination=$@ $<

%.zip: %/index.html $$(call rwildcard,$$*,*)
	-$(RM) $(subst /,$(sep),$@)
	$(ZIP) -r $@ $* $(ZIP_EXCLUDE)$*$(sep)LaTeXML.cache
