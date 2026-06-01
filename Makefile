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
                 opentunex-top-down-bottleneck

.PHONY: all install clean test

all: install

install: install-skills

install-skills:
	install -d $(SKILLS_DIR)
	for skill in skills/*/opentunex-*; do \
		[ -d "$$skill" ] || continue; \
		basename=$$(basename $$skill); \
		case " $(INCLUDE_SKILLS) " in *" $$basename "*) ;; *) continue;; esac; \
		install -d $(SKILLS_DIR)/$$basename; \
		for subdir in references scripts; do \
			[ -d "$$skill/$$subdir" ] && install -d $(SKILLS_DIR)/$$basename/$$subdir; \
			[ -d "$$skill/$$subdir" ] && for f in $$skill/$$subdir/*; do \
				[ -f "$$f" ] && install -m 644 $$f $(SKILLS_DIR)/$$basename/$$subdir/; \
			done; \
		done; \
		install -m 644 $$skill/SKILL.md $(SKILLS_DIR)/$$basename/; \
	done
	@echo "Installed skills to $(SKILLS_DIR)"

clean:
	rm -rf $(SKILLS_DIR)/opentunex-*
	@echo "Cleaned skills from $(SKILLS_DIR)"

test: test-skills

test-skills:
	@echo "=== SKILL.md Format Validation ==="
	@errors=0; \
	for skill in skills/*/opentunex-*; do \
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
		name_val=$$(echo "$$name_line" | sed 's/^name: *//'); \
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