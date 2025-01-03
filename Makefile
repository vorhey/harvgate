.PHONY: test watch

# Run tests once
test:
	nvim --headless -c "PlenaryBustedDirectory tests" || exit 0

# Watch for changes and run tests automatically
watch:
	@echo "Watching for changes..."
	@find lua tests -name '*.lua' | entr -c make test

# Clean any generated files (if needed later)
clean:
	@echo "Cleaning..."
	@find . -name '*.tmp' -delete

# Default target
.DEFAULT_GOAL := test
