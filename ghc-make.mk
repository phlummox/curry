# Specific rules for building with ghc --make
# $Id: ghc-make.mk 1834 2005-11-12 15:13:00Z wlux $
#
# Copyright (c) 2002-2005, Wolfgang Lux
# See LICENSE for the full license.
#

# specific definitions for ghc
GHC_HCFLAGS = -H12m # -Rghc-timing

# programs
cycc: $(cycc_SRCS)
	@case "$(MFLAGS)" in -*s*) s=-v0;; *) s=;; esac; \
	$(HC) --make $(HCFLAGS) $(GHC_HCFLAGS) $$s -o $@ $@
cymk: $(cymk_SRCS)
	@case "$(MFLAGS)" in -*s*) s=-v0;; *) s=;; esac; \
	$(HC) --make $(HCFLAGS) $(GHC_HCFLAGS) $$s -o $@ $@
newer: $(newer_SRCS)
	@case "$(MFLAGS)" in -*s*) s=-v0;; *) s=;; esac; \
	$(HC) --make $(HCFLAGS) $(GHC_HCFLAGS) $$s -o $@ $@
cam2c: $(cam2c_SRCS)
	@case "$(MFLAGS)" in -*s*) s=-v0;; *) s=;; esac; \
	$(HC) --make $(HCFLAGS) $(GHC_HCFLAGS) $$s -o $@ $@
mach: $(mach_SRCS)
	@case "$(MFLAGS)" in -*s*) s=-v0;; *) s=;; esac; \
	$(HC) --make $(HCFLAGS) $(GHC_HCFLAGS) $$s -o $@ $@

# compute the dependencies
depend-dir:
	@: Do not delete this line
