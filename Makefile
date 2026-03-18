NAME=thesis
ABSTRACT=abstract
LATEXMKOPTS=-pdflua #you can also use -pdf for forcing pdflatex, if required
LATEXMK=latexmk $(LATEXMKOPTS)
PANDOCOPTS=--top-level-division=chapter --listings --lua-filter crossref-gen.lua --filter pandoc-crossref --biblatex
BUILD_DIR := ./build
CHAPTERS=$(addprefix $(BUILD_DIR)/, $(basename $(wildcard *.md)))
LATEX_TEMPLATE=$(addprefix $(BUILD_DIR)/, $(notdir $(wildcard latex_template/*.tex latex_template/*.xmpdata)))

all: $(addsuffix .tex, $(CHAPTERS)) $(LATEX_TEMPLATE) | $(BUILD_DIR)
	rsync -av refs.bib $(BUILD_DIR)
	rsync -av img $(BUILD_DIR)
	rsync -av latex_template/latex_img $(BUILD_DIR)
	rsync macros.tex $(BUILD_DIR)
	
	cd $(BUILD_DIR); \
		$(LATEXMK) $(NAME); \
		$(LATEXMK) $(ABSTRACT)-cz; \
		$(LATEXMK) $(ABSTRACT)-en

# Building latex templates
define BUILD_TEMPLATE
	pandoc -t latex -o $@ --metadata-file=metadata.yaml --template=$< < /dev/null
endef
$(BUILD_DIR)/%.tex: latex_template/%.tex metadata.yaml | $(BUILD_DIR)
	$(BUILD_TEMPLATE)
$(BUILD_DIR)/%.xmpdata: latex_template/%.xmpdata metadata.yaml | $(BUILD_DIR)
	$(BUILD_TEMPLATE)

# general building of chapters
$(BUILD_DIR)/%.tex: %.md crossref-gen.lua metadata.yaml | $(BUILD_DIR)
	pandoc $(PANDOCOPTS) -f markdown -t latex --metadata-file=metadata.yaml -o $@ $<

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

clean:
	rm -rf $(BUILD_DIR)

