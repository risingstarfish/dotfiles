Subject: harden FATCAT's input parsing — exit(1) with error message / overflowing on bad PDBs

Before beginning, read Readme.md in full. Everythign pertaining to the build flow, CLI output naming, and
two verification tests are all explained there.

Current issue: PROT::AssignPdb in Prot.C will exit(1) in the middle of parsing and it does unchecked
strcpy/sprintf into a fixed char str[50000] against the MAXLEN 5000 cap that's sitting in basic.h. If a
truncated or oversized PDB file is inputted, it either dies with zero message or silently overflows. I would like
that turned into an error message that describes what went wrong and on which line parsing errored (if applicable).
Then continue with exit (1). Oversized pdb files should be rejected instead of silently overflowing.

You should handle the error with a single error channel throughout the parse/execution. The codebase's idiom is a
status int with return -1. You should change that to either a struct containing an error code and error message
or return an enum PdbErr {PDB_OK, PDB_MALFORMED, PDB_TRUNCATED, PDB_TOO_LONG, PDB_ALLOC} (edit as needed) as error codes and create an enum_to_string function that maps the enum to string message. Ensure to stick with whatever method chosen throughout the execution: PROT::AssignPdb -> the AFPCHAIN constructor in AFPchain.C (it builds the two PROTs, then runs ExtractAfp/SortAfp) -> main in FATCAT.C. The alignment-side parsers are the same: POSTALIGN::ReadPdb, ReadFastaAln, and ReadClustalAln in PostAlign.C, which feed the separate PostFATCAT binary.

NOTICE:FATCAT2Tree.C also constructs AFPCHAIN so whatever you change on the constructor or the Prot.h
interface has to keep that binary compiling and behaving identically.Similarly, PostFATCAT is its own link unit and doesn't share the AFPCHAIN path, so handle it in parallel.

Hold the output byte-identical on any valid input, not the error path. The <prefix>.aln, the
one-line short report from ShtReport/Report in FATCAT.C, and the .ps/.pdb/.script artifacts all named per the
<prefix>.<ext> convention in AFPchain.C. I'm calling out the report line specifically because it's a real contract:
FATCATDB (report/extalign/extprob in FATCATDBSearch.C) and the two Perl reimplementations
fatcatparser.pl/fatcatparser_t.pl all parse it. Reorder a field or change a number's format and your local diff goes
green while you have quietly broken three downstream consumers. That is the only potential trap.

Scope: Do not convert the recursive ALIGN0::Trace backtrace in Align0.C to iterative (its call depth is the alignment length, it's a stack risk near MAXLEN, and it's not your job today). Do not rewrite the manual new[]/delete[] lifetime on the ~25 AFPCHAIN members. Do not add -fopenmp to the Makefile to make the #pragma omp parallel for at FATCATSearch.C:90 "work" — it's a deliberate no-op under the checked-in flags.Leave the latent unopened-ofstream write in AFPCHAIN::Display at mod==1 (around line 2007) alone(it's a separate change).

Verify it the only way this project has a notion of verifying, which is: run ./Install (it swaps the modern headers
from basic_90.h or basic_73.h into basic.h). If ./Install fails in your env, manually comment out the missign headers then run `make`.Then the fast test, in Examples_FATCAT/:
FATCAT -p1 1a21A.pdb -p2 1hwgC.pdb -o 1a21A_1hwgC -m -ac -t, and diff 1a21A_1hwgC.aln compare.aln. Zero output means it ran ok. The full one, in Example2_FATCAT/: ../FATCATMain/FATCATQue.pl timeused allpair.list -q > allpair.aln
(that's 15 PDBs, the Readme says ~30 min on a 1.8GHz Xeon), and diff allpair.aln allpair.aln.comp.

The Readme's smaller-pair test references prtpair.list, but the file
actually in the tree is patpair.list. Follow the intent (run the ~10-min subset), use the real filename, and call the
mismatch out. Also the Readme's Program-3 section labels FATCATSearch.pl's command as FATCATQue.pl. Do not modify and doc bugs.

When you are done I would like:
(a) the error contract: the struct string and status code OR the enum values and pdbErrStr mapping (each value → its message), the exit code per value, and the exact stderr text main prints; say whether you carried "where" as a separate lineNo out-param rather than piling it onto the enum;
(b) the verification transcript with the actual diff results;
(c) the list of out-of-scope things and why you left them;
(d) the prtpair/patpair reconciliation;
(e) the exact g++/make flags you used and any behavioral difference, however small, between the legacy and the regenerated basic.h so I can trust the byte-identical claim.
