--  `fix` command (spec section 9.3 MAY): the first command in ada-FuSa
--  that can write to a user's actual source files, rather than only a
--  `.fusa-*.json` sidecar or a generated report -- a meaningfully more
--  consequential action than anything else this tool does. Scope is
--  deliberately narrow: ONLY whitespace/formatting transforms that are
--  100% mechanical and carry zero semantic risk (the exact set LINT001-
--  003 and ADA006 already flag). It never touches anything that requires
--  a judgement call -- an unjustified "pragma Suppress", a line-length
--  violation that would need re-wrapping, a security finding -- since
--  "safe to auto-apply" and "safe to auto-decide" are different claims,
--  and this tool only ever makes the first one.
--
--  The `fix` command itself defaults to a dry run (report what would
--  change) and requires an explicit `--apply` to write anything -- see
--  Fusa.Cli.Cmd_Fix.

package Fusa.Fix is

   --  Applies, in one pass:
   --    - every tab character replaced with a single space (ADA006);
   --    - trailing whitespace stripped from every line (LINT001);
   --    - a run of more than one consecutive blank line collapsed to
   --      exactly one (LINT002);
   --    - the file normalised to end with exactly one trailing newline,
   --      neither zero nor more than one (LINT003).
   --  Idempotent: Fix_Content (Fix_Content (S)) = Fix_Content (S).
   --  fusa:req REQ-116
   function Fix_Content (Content : String) return String;

end Fusa.Fix;
