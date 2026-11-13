LINK99 SBC TESTS
================

Step 0 is a build-pipeline test only.

Step 1 will add small canonical REL fixtures and expected SEEREL-style
record dumps.  From Step 2 onward every linker test should be run through
both:

  1. the current Windows LINK99 (oracle), and
  2. SBC LINK99 (candidate)

and the generated addresses/images compared where the output models match.
