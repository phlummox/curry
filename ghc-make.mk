# Specific rules for building with ghc --make
# $Id: ghc-make.mk 3167 2015-08-26 12:54:14Z wlux $
#
# Copyright (c) 2002-2015, Wolfgang Lux
# See LICENSE for the full license.
#

# specific definitions for ghc
GHC_HFLAGS = -H12m -i$(HASKELL) -i$(HC_PATH_STYLE)

# programs
# NB The seemingly contrived $(MAKEFLAGS:M-s:S/=/=/) substitution is used in
#    order to check for the presence of -s among the command line flags in
#    a portable way. GNU make and other POSIX compatible make commands
#    collect all single letter options -- if any -- in the first word of
#    $(MAKEFLAGS). BSD make commands, on the other hand, use a separate word
#    for each single letter option. In order to make the -s option the first
#    word if present, we use BSD make's :M variable modifier, which filters
#    $(MAKEFLAGS) keeping only those words which match the pattern following
#    :M. Since other make commands do not understand this modifier, we also
#    add the identity substitution :S/=/=/, which yields a System V compatible
#    variable substitution of the form :SUFFIX=REPL.
cycc: $(cycc_SRCS)
	@set dummy $(MAKEFLAGS:M-s:S/=/=/); \
	case $$2 in *=*) s=;; *s*) s=-v0;; *) s=;; esac; \
	$(HC) --make $(HFLAGS) $(GHC_HFLAGS) $$s -o $@ $@
cymk: $(cymk_SRCS)
	@set dummy $(MAKEFLAGS:M-s:S/=/=/); \
	case $$2 in *=*) s=;; *s*) s=-v0;; *) s=;; esac; \
	$(HC) --make $(HFLAGS) $(GHC_HFLAGS) $$s -o $@ $@
newer: $(newer_SRCS)
	@set dummy $(MAKEFLAGS:M-s:S/=/=/); \
	case $$2 in *=*) s=;; *s*) s=-v0;; *) s=;; esac; \
	$(HC) --make $(HFLAGS) $(GHC_HFLAGS) $$s -o $@ $@
cam2c: $(cam2c_SRCS)
	@set dummy $(MAKEFLAGS:M-s:S/=/=/); \
	case $$2 in *=*) s=;; *s*) s=-v0;; *) s=;; esac; \
	$(HC) --make $(HFLAGS) $(GHC_HFLAGS) $$s -o $@ $@
mach: $(mach_SRCS)
	@set dummy $(MAKEFLAGS:M-s:S/=/=/); \
	case $$2 in *=*) s=;; *s*) s=-v0;; *) s=;; esac; \
	$(HC) --make $(HFLAGS) $(GHC_HFLAGS) $$s -o $@ $@

# compute the dependencies
depend-dir:
	@: Do not delete this line
