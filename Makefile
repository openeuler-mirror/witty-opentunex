# Makefile for opentunex
# Usage: make install PREFIX=$HOME/.opencode
#        make test

PREFIX ?= $(HOME)/.opencode
DESTDIR ?=

SKILLS_DIR = $(DESTDIR)$(PREFIX)/skills

INCLUDE_SKILLS = opentunex-remote-execution \
                 opentunex-io-bottleneck \
                 opentunex-lock-bottleneck \
                 opentunex-mem-bottleneck \
                 opentunex-net-bottleneck \
                 opentunex-sched-bottleneck \
                 opentunex-top-down-bottleneck \
                 opentunex-application-bottleneck \
                 opentunex-bottleneck-analysis \
                 opentunex-scenario-bottleneck \
                 opentunex-data-collection \
                 opentunex-application-optimization \
                 opentunex-inference-core-binding-optimization \
                 opentunex-os-performance-optimization \
                 opentunex-performance-tuning \
                 opentunex-scenario-tuning \
                 witty-opentunex

.PHONY: all install clean test

all: install

install: install-skills

install-skills:
	install -d $(SKILLS_DIR)
	install_one_skill() { \
		local _src="$$1"; \
		local _dest="$$2"; \
		install -d "$$_dest"; \
		for _sub in references scripts; do \
			[ -d "$$_src/$$_sub" ] || continue; \
			install -d "$$_dest/$$_sub"; \
			for _f in "$$_src/$$_sub"/*; do \
				[ -f "$$_f" ] && install -m 644 "$$_f" "$$_dest/$$_sub/"; \
			done; \
		done; \
		[ -f "$$_src/SKILL.md" ] && install -m 644 "$$_src/SKILL.md" "$$_dest/"; \
		for _sub in "$$_src"/opentunex-*; do \
			[ -d "$$_sub" ] || continue; \
			install_one_skill "$$_sub" "$$_dest/$$(basename "$$_sub")"; \
		done; \
	}; \
	for skill in skills/*/opentunex-* skills/witty-opentunex; do \
		[ -d "$$skill" ] || continue; \
		basename=$$(basename $$skill); \
		case " $(INCLUDE_SKILLS) " in *" $$basename "*) ;; *) continue;; esac; \
		install_one_skill "$$skill" "$(SKILLS_DIR)/$$basename"; \
	done
	@echo "Installed skills to $(SKILLS_DIR)"

clean:
	rm -rf $(SKILLS_DIR)/opentunex-* $(SKILLS_DIR)/witty-opentunex
	@echo "Cleaned skills from $(SKILLS_DIR)"

test: test-skills

test-skills:
	@echo "=== SKILL.md Format Validation ==="
	@errors=0; \
	for skill in skills/*/opentunex-* skills/witty-opentunex; do \
		[ -d "$$skill" ] || continue; \
		basename=$$(basename $$skill); \
		case " $(INCLUDE_SKILLS) " in *" $$basename "*) ;; *) continue;; esac; \
		skill_md="$$skill/SKILL.md"; \
		echo "validating: $$skill_md" ; \
		if [ ! -f "$$skill_md" ]; then \
			echo "ERROR: $$basename/SKILL.md not found"; \
			errors=$$((errors + 1)); \
			continue; \
		fi; \
		if ! grep -q "^---$$" "$$skill_md"; then \
			echo "ERROR: $$basename/SKILL.md missing opening '---'"; \
			errors=$$((errors + 1)); \
		fi; \
		if ! grep -q "^name: " "$$skill_md"; then \
			echo "ERROR: $$basename/SKILL.md missing 'name:' field"; \
			errors=$$((errors + 1)); \
		fi; \
		if ! grep -q "^description: " "$$skill_md"; then \
			echo "ERROR: $$basename/SKILL.md missing 'description:' field"; \
			errors=$$((errors + 1)); \
		fi; \
		if ! grep -q "^---$$" "$$skill_md" | tail -1; then \
			echo "ERROR: $$basename/SKILL.md missing closing '---'"; \
			errors=$$((errors + 1)); \
		fi; \
		name_line=$$(grep "^name: " "$$skill_md" | head -1); \
		name_val=$$(echo "$$name_line" | sed 's/^name: *"\(.*\)"$$/\1/; t; s/^name: *//'); \
		if [ "$$name_val" != "$$basename" ]; then \
			echo "ERROR: $$basename/SKILL.md name mismatch (expected '$$basename', got '$$name_val')"; \
			errors=$$((errors + 1)); \
		fi; \
	done; \
	if [ $$errors -eq 0 ]; then \
		echo "All SKILL.md files validated successfully"; \
	else \
		echo "Validation failed with $$errors error(s)"; \
		exit 1; \
	fi