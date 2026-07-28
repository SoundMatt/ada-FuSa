with Ada.Strings.Fixed;
with Fusa.Files;

package body Fusa.Rules_Lint is

   function Has_Suffix (S, Suffix : String) return Boolean is
     (S'Length >= Suffix'Length
      and then S (S'Last - Suffix'Length + 1 .. S'Last) = Suffix);

   function Scan
     (Project_Root : String; Files : String_List) return Finding_List
   is
      Result : Finding_List;
   begin
      for Rel of Files loop
         if Has_Suffix (Rel, ".ads") or else Has_Suffix (Rel, ".adb") then
            declare
               Full : constant String := Fusa.Files.Join (Project_Root, Rel);
            begin
               if Fusa.Files.Exists (Full) then
                  declare
                     Content : constant String := Fusa.Files.Read_File (Full);
                     Lines   : constant String_List := Fusa.Files.Split_Lines (Content);
                     Blank_Run : Natural := 0;
                  begin
                     --  LINT001: trailing whitespace at end of a line.
                     --  LINT002: a second (or later) consecutive blank
                     --  line -- flagged once per run, at the first
                     --  "extra" blank line, not once per file.
                     for I in 1 .. Natural (Lines.Length) loop
                        declare
                           Line : constant String := Lines.Element (I);
                        begin
                           if Line'Length > 0
                             and then (Line (Line'Last) = ' ' or else Line (Line'Last) = ASCII.HT)
                           then
                              Result.Append
                                (Make_Finding
                                   (Rule_Id     => "LINT001",
                                    Severity    => Warning,
                                    Message     => "line has trailing whitespace",
                                    Loc         => Make_Location (Rel, I),
                                    Category    => Fusa.Lint,
                                    Remediation => "remove the trailing space/tab character(s)"));
                           end if;

                           if Ada.Strings.Fixed.Trim (Line, Ada.Strings.Both)'Length = 0 then
                              Blank_Run := Blank_Run + 1;
                              if Blank_Run = 2 then
                                 Result.Append
                                   (Make_Finding
                                      (Rule_Id     => "LINT002",
                                       Severity    => Warning,
                                       Message     => "multiple consecutive blank lines",
                                       Loc         => Make_Location (Rel, I),
                                       Category    => Fusa.Lint,
                                       Remediation =>
                                         "collapse the run of blank lines to a single one"));
                              end if;
                           else
                              Blank_Run := 0;
                           end if;
                        end;
                     end loop;

                     --  LINT003: the file's raw bytes should end with
                     --  exactly one LF -- neither missing (no trailing
                     --  newline at all) nor more than one (trailing blank
                     --  line(s) at end of file).
                     if Content'Length > 0 then
                        if Content (Content'Last) /= ASCII.LF then
                           Result.Append
                             (Make_Finding
                                (Rule_Id     => "LINT003",
                                 Severity    => Warning,
                                 Message     => "file does not end with a trailing newline",
                                 Loc         => Make_Location (Rel, Natural (Lines.Length)),
                                 Category    => Fusa.Lint,
                                 Remediation => "add a trailing newline at the end of the file"));
                        elsif Content'Length > 1
                          and then Content (Content'Last - 1) = ASCII.LF
                        then
                           Result.Append
                             (Make_Finding
                                (Rule_Id     => "LINT003",
                                 Severity    => Warning,
                                 Message     => "file ends with more than one trailing newline",
                                 Loc         => Make_Location (Rel, Natural (Lines.Length)),
                                 Category    => Fusa.Lint,
                                 Remediation =>
                                   "remove the extra blank line(s) at the end of the file"));
                        end if;
                     end if;
                  end;
               end if;
            end;
         end if;
      end loop;
      return Result;
   end Scan;

end Fusa.Rules_Lint;
