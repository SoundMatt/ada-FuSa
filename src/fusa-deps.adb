with Ada.Strings.Fixed;
with Fusa.Files;

package body Fusa.Deps is

   function Has_Suffix (S, Suffix : String) return Boolean is
     (S'Length >= Suffix'Length
      and then S (S'Last - Suffix'Length + 1 .. S'Last) = Suffix);

   function Starts_With (S, Prefix : String) return Boolean is
     (S'Length >= Prefix'Length
      and then S (S'First .. S'First + Prefix'Length - 1) = Prefix);

   function To_Upper (S : String) return String is
      Result : String (S'Range);
   begin
      for I in S'Range loop
         if S (I) in 'a' .. 'z' then
            Result (I) := Character'Val (Character'Pos (S (I)) - 32);
         else
            Result (I) := S (I);
         end if;
      end loop;
      return Result;
   end To_Upper;

   --  Everything from the first "--" onward is a comment (this only ever
   --  runs on context-clause lines, which never contain string literals
   --  in practice, so no quote-awareness is needed here).
   function Strip_Comment (Line : String) return String is
   begin
      for I in Line'First .. Line'Last - 1 loop
         if Line (I) = '-' and then Line (I + 1) = '-' then
            return Line (Line'First .. I - 1);
         end if;
      end loop;
      return Line;
   end Strip_Comment;

   function Extract_Name (Decl_After_Keyword : String) return String is
      Trimmed : constant String :=
        Ada.Strings.Fixed.Trim (Decl_After_Keyword, Ada.Strings.Left);
   begin
      for I in Trimmed'Range loop
         if Trimmed (I) = ' ' or else Trimmed (I) = '(' or else Trimmed (I) = ';' then
            return Trimmed (Trimmed'First .. I - 1);
         end if;
      end loop;
      return Trimmed;
   end Extract_Name;

   function Split_Csv (S : String) return String_List is
      Result : String_List;
      Start  : Positive := S'First;
   begin
      if S'Length = 0 then
         return Result;
      end if;
      for I in S'Range loop
         if S (I) = ',' then
            declare
               Piece : constant String :=
                 Ada.Strings.Fixed.Trim (S (Start .. I - 1), Ada.Strings.Both);
            begin
               if Piece'Length > 0 then
                  Result.Append (Piece);
               end if;
            end;
            Start := I + 1;
         end if;
      end loop;
      declare
         Piece : constant String :=
           Ada.Strings.Fixed.Trim (S (Start .. S'Last), Ada.Strings.Both);
      begin
         if Piece'Length > 0 then
            Result.Append (Piece);
         end if;
      end;
      return Result;
   end Split_Csv;

   --  A with-clause's argument list, terminated at the first ';' (a
   --  context-clause "with" is always a simple statement -- no need to
   --  handle nested semicolons).
   function With_Names (After_Keyword : String) return String_List is
      Semi : Natural := 0;
   begin
      for I in After_Keyword'Range loop
         if After_Keyword (I) = ';' then
            Semi := I;
            exit;
         end if;
      end loop;
      if Semi = 0 then
         return Split_Csv (After_Keyword);
      end if;
      return Split_Csv (After_Keyword (After_Keyword'First .. Semi - 1));
   end With_Names;

   function Contains_Ci (L : String_List; S : String) return Boolean is
   begin
      for E of L loop
         if To_Upper (E) = To_Upper (S) then
            return True;
         end if;
      end loop;
      return False;
   end Contains_Ci;

   type Extraction is record
      Name  : Unbounded_String;
      Withs : String_List;
   end record;

   function Extract_Unit (Content : String) return Extraction is
      Lines  : constant String_List := Fusa.Files.Split_Lines (Content);
      Result : Extraction;
   begin
      for Raw_Line of Lines loop
         declare
            Trimmed : constant String :=
              Ada.Strings.Fixed.Trim (Strip_Comment (Raw_Line), Ada.Strings.Both);
            Upper   : constant String := To_Upper (Trimmed);
         begin
            if Trimmed'Length = 0 then
               null;
            elsif Starts_With (Upper, "PRIVATE WITH ") then
               for N of With_Names (Trimmed (Trimmed'First + 13 .. Trimmed'Last)) loop
                  Result.Withs.Append (N);
               end loop;
            elsif Starts_With (Upper, "WITH ") then
               for N of With_Names (Trimmed (Trimmed'First + 5 .. Trimmed'Last)) loop
                  Result.Withs.Append (N);
               end loop;
            elsif Starts_With (Upper, "PACKAGE ") then
               declare
                  Rest       : constant String :=
                    Ada.Strings.Fixed.Trim
                      (Trimmed (Trimmed'First + 8 .. Trimmed'Last), Ada.Strings.Left);
                  Rest_Upper : constant String := To_Upper (Rest);
               begin
                  if Starts_With (Rest_Upper, "BODY ") then
                     Result.Name :=
                       To_Unbounded_String (Extract_Name (Rest (Rest'First + 5 .. Rest'Last)));
                  else
                     Result.Name := To_Unbounded_String (Extract_Name (Rest));
                  end if;
               end;
               exit;
            elsif Starts_With (Upper, "PROCEDURE ") or else Starts_With (Upper, "FUNCTION ") then
               declare
                  Kw_Len : constant Positive :=
                    (if Starts_With (Upper, "FUNCTION ") then 9 else 10);
               begin
                  Result.Name :=
                    To_Unbounded_String
                      (Extract_Name (Trimmed (Trimmed'First + Kw_Len .. Trimmed'Last)));
               end;
               exit;
            end if;
         end;
      end loop;
      return Result;
   end Extract_Unit;

   function Analyze (Project_Root : String; Files : String_List) return Dep_Node_List is
      Result : Dep_Node_List;
   begin
      for Rel of Files loop
         if Has_Suffix (Rel, ".ads") or else Has_Suffix (Rel, ".adb") then
            declare
               Full : constant String := Fusa.Files.Join (Project_Root, Rel);
            begin
               if Fusa.Files.Exists (Full) then
                  declare
                     Ex    : constant Extraction := Extract_Unit (Fusa.Files.Read_File (Full));
                     Found : Boolean := False;
                  begin
                     if Length (Ex.Name) > 0 then
                        for I in 1 .. Natural (Result.Length) loop
                           if To_Upper (To_String (Result.Element (I).Name)) =
                             To_Upper (To_String (Ex.Name))
                           then
                              declare
                                 Node : Dep_Node := Result.Element (I);
                              begin
                                 Node.Files.Append (Rel);
                                 for W of Ex.Withs loop
                                    Node.Deps.Append (W);
                                 end loop;
                                 Result.Replace_Element (I, Node);
                              end;
                              Found := True;
                              exit;
                           end if;
                        end loop;
                        if not Found then
                           declare
                              Node : Dep_Node;
                           begin
                              Node.Name := Ex.Name;
                              Node.Files.Append (Rel);
                              Node.Deps := Ex.Withs;
                              Result.Append (Node);
                           end;
                        end if;
                     end if;
                  end;
               end if;
            end;
         end if;
      end loop;

      --  Second pass: keep only intra-project dependencies, deduplicated,
      --  and never a self-edge.
      for I in 1 .. Natural (Result.Length) loop
         declare
            Node     : Dep_Node := Result.Element (I);
            Filtered : String_List;
         begin
            for D of Node.Deps loop
               declare
                  Is_Known : Boolean := False;
               begin
                  for Other of Result loop
                     if To_Upper (To_String (Other.Name)) = To_Upper (D) then
                        Is_Known := True;
                        exit;
                     end if;
                  end loop;
                  if Is_Known and then To_Upper (D) /= To_Upper (To_String (Node.Name))
                    and then not Contains_Ci (Filtered, D)
                  then
                     Filtered.Append (D);
                  end if;
               end;
            end loop;
            Node.Deps := Filtered;
            Result.Replace_Element (I, Node);
         end;
      end loop;

      return Result;
   end Analyze;

   function Find_By_File (Nodes : Dep_Node_List; Rel_Path : String) return Dep_Node is
      Empty : Dep_Node;
   begin
      for N of Nodes loop
         for F of N.Files loop
            if F = Rel_Path then
               return N;
            end if;
         end loop;
      end loop;
      return Empty;
   end Find_By_File;

   function Reverse_Reachable (Nodes : Dep_Node_List; Target_Name : String) return Dep_Node_List is
      Result   : Dep_Node_List;
      Visited  : String_List;
      Frontier : String_List;
   begin
      Frontier.Append (Target_Name);
      while not Frontier.Is_Empty loop
         declare
            Next_Frontier : String_List;
         begin
            for Cur of Frontier loop
               for N of Nodes loop
                  if Contains_Ci (N.Deps, Cur)
                    and then not Contains_Ci (Visited, To_String (N.Name))
                    and then To_Upper (To_String (N.Name)) /= To_Upper (Target_Name)
                  then
                     Visited.Append (To_String (N.Name));
                     Result.Append (N);
                     Next_Frontier.Append (To_String (N.Name));
                  end if;
               end loop;
            end loop;
            Frontier := Next_Frontier;
         end;
      end loop;
      return Result;
   end Reverse_Reachable;

end Fusa.Deps;
