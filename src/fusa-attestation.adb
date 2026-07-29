with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Fusa.Json;
with Fusa.Sha256;
use type Fusa.Json.Value_Access;

package body Fusa.Attestation is

   function Parse (Root : Fusa.Json.Value_Access) return Info is
      Result : Info;
      Att    : constant Fusa.Json.Value_Access :=
        Fusa.Json.Get_Member (Root, "attestation");
   begin
      if Att = null or else not Fusa.Json.Is_Object (Att) then
         return Result;
      end if;
      Result.Present := True;
      Result.Status := To_Unbounded_String
        (Fusa.Json.Get_String (Att, "status", "heuristic"));
      Result.Implementation_Author := To_Unbounded_String
        (Fusa.Json.Get_String (Att, "implementationAuthor"));
      Result.Independent_Reviewer := To_Unbounded_String
        (Fusa.Json.Get_String (Att, "independentReviewer"));
      Result.Reviewed_At :=
        To_Unbounded_String (Fusa.Json.Get_String (Att, "reviewedAt"));
      Result.Content_Hash :=
        To_Unbounded_String (Fusa.Json.Get_String (Att, "contentHash"));
      return Result;
   end Parse;

   Q : constant Character := '"';

   function Jcs_Escape (S : String) return String is
      Buf : Unbounded_String := Null_Unbounded_String;
   begin
      for C of S loop
         case C is
            when '"'  => Append (Buf, '\' & '"');
            when '\'  => Append (Buf, '\' & '\');
            when Character'Val (8)  => Append (Buf, '\' & 'b');
            when Character'Val (9)  => Append (Buf, '\' & 't');
            when Character'Val (10) => Append (Buf, '\' & 'n');
            when Character'Val (12) => Append (Buf, '\' & 'f');
            when Character'Val (13) => Append (Buf, '\' & 'r');
            when others =>
               if Character'Pos (C) < 16#20# then
                  declare
                     Hex : constant String := "0123456789abcdef";
                     Hi  : constant Natural := Character'Pos (C) / 16;
                     Lo  : constant Natural := Character'Pos (C) mod 16;
                  begin
                     Append (Buf, '\' & 'u' & "00" &
                               Hex (Hi + 1 .. Hi + 1) &
                               Hex (Lo + 1 .. Lo + 1));
                  end;
               else
                  Append (Buf, C);
               end if;
         end case;
      end loop;
      return To_String (Buf);
   end Jcs_Escape;

   function Jstr (S : String) return String is (Q & Jcs_Escape (S) & Q);

   function Trim_Sign (Img : String) return String is
     (if Img (Img'First) = ' ' then Img (Img'First + 1 .. Img'Last) else Img);

   function Format_Number (N : Long_Float) return String is
   begin
      --  Every number this actually applies to (severities, counts,
      --  ratios) is a small integer, but Root can hold any document a
      --  human hand-edits -- a stray extra digit or fat-fingered huge
      --  value must not crash the hash computation. Guard the
      --  Long_Long_Integer conversion's range explicitly rather than
      --  letting it raise Constraint_Error uncaught; the fallback stays
      --  deterministic (same input -> same output), just not
      --  JCS-perfect for magnitudes no real artifact would ever contain.
      if N >= Long_Float (Long_Long_Integer'First)
        and then N <= Long_Float (Long_Long_Integer'Last)
      then
         return Trim_Sign (Long_Long_Integer'Image (Long_Long_Integer (N)));
      else
         return Trim_Sign (Long_Float'Image (N));
      end if;
   end Format_Number;

   function Encode_Value (V : Fusa.Json.Value_Access) return String;

   function Encode_Members
     (Members : Fusa.Json.Member_Vectors.Vector;
      Exclude : Fusa.String_List) return String
   is
      function Excluded (Key : String) return Boolean is
      begin
         for E of Exclude loop
            if E = Key then
               return True;
            end if;
         end loop;
         return False;
      end Excluded;

      Keys : Fusa.String_List;
   begin
      for M of Members loop
         if not Excluded (To_String (M.Key)) then
            Keys.Append (To_String (M.Key));
         end if;
      end loop;

      --  Lexicographic key order (RFC 8785 JCS) via simple insertion sort
      --  -- these member lists are always small.
      for I in 2 .. Natural (Keys.Length) loop
         declare
            Key_I : constant String := Keys.Element (I);
            J     : Natural := I - 1;
         begin
            while J >= 1 and then Keys.Element (J) > Key_I loop
               Keys.Replace_Element (J + 1, Keys.Element (J));
               J := J - 1;
            end loop;
            Keys.Replace_Element (J + 1, Key_I);
         end;
      end loop;

      declare
         Buf   : Unbounded_String := To_Unbounded_String ("{");
         First : Boolean := True;
      begin
         for K of Keys loop
            if not First then
               Append (Buf, ",");
            end if;
            First := False;
            for M of Members loop
               if To_String (M.Key) = K then
                  Append (Buf, Jstr (K) & ":" & Encode_Value (M.Val));
                  exit;
               end if;
            end loop;
         end loop;
         Append (Buf, "}");
         return To_String (Buf);
      end;
   end Encode_Members;

   function Encode_Value (V : Fusa.Json.Value_Access) return String is
      use Fusa.Json;
      Empty : Fusa.String_List;
   begin
      if V = null then
         return "null";
      end if;
      case V.Kind is
         when Json_Null   => return "null";
         when Json_Bool   => return (if V.Bool_Val then "true" else "false");
         when Json_Number => return Format_Number (V.Num_Val);
         when Json_String => return Jstr (To_String (V.Str_Val));
         when Json_Array  =>
            declare
               Buf   : Unbounded_String := To_Unbounded_String ("[");
               First : Boolean := True;
            begin
               for Item of V.Items loop
                  if not First then
                     Append (Buf, ",");
                  end if;
                  First := False;
                  Append (Buf, Encode_Value (Item));
               end loop;
               Append (Buf, "]");
               return To_String (Buf);
            end;
         when Json_Object =>
            return Encode_Members (V.Members, Empty);
      end case;
   end Encode_Value;

   function Canonical_Content_Hash
     (Root : Fusa.Json.Value_Access) return String
   is
      Exclude : Fusa.String_List;
   begin
      Exclude.Append ("attestation");
      Exclude.Append ("generatedAt");
      if Root = null or else not Fusa.Json.Is_Object (Root) then
         return "sha256:" & Fusa.Sha256.Hex_Digest ("{}");
      end if;
      return "sha256:" &
        Fusa.Sha256.Hex_Digest (Encode_Members (Root.Members, Exclude));
   end Canonical_Content_Hash;

   --  Identity comparison for the independence check below: trimmed and
   --  case-folded, so "Jane Doe" / "Jane Doe " / "JANE DOE" are all
   --  recognised as the same self-attesting identity rather than
   --  trivially bypassing the anti-self-review gate on whitespace or
   --  casing alone. Still not full identity resolution (a display name
   --  vs. an email for the same real person won't be caught) -- that is
   --  a human-process concern this tool cannot verify.
   function Normalize_Identity (S : Unbounded_String) return String is
     (Ada.Characters.Handling.To_Lower
        (Ada.Strings.Fixed.Trim (To_String (S), Ada.Strings.Both)));

   function Is_Fresh_Reviewed
     (Att : Info; Root : Fusa.Json.Value_Access) return Boolean
   is
   begin
      if not Att.Present or else To_String (Att.Status) /= "reviewed" then
         return False;
      end if;
      if Normalize_Identity (Att.Independent_Reviewer)'Length = 0
        or else Normalize_Identity (Att.Independent_Reviewer)
                  = Normalize_Identity (Att.Implementation_Author)
      then
         return False;
      end if;
      if Length (Att.Content_Hash) = 0 then
         return False;
      end if;
      return To_String (Att.Content_Hash) = Canonical_Content_Hash (Root);
   end Is_Fresh_Reviewed;

   procedure Write (W : in out Fusa.Json.Writer.Instance; Att : Info) is
   begin
      if not Att.Present then
         return;
      end if;
      W.Key ("attestation");
      W.Object_Start;
      W.Field ("status", To_String (Att.Status));
      W.Field_If_Non_Blank
        ("implementationAuthor", To_String (Att.Implementation_Author));
      W.Field_If_Non_Blank
        ("independentReviewer", To_String (Att.Independent_Reviewer));
      W.Field_If_Non_Blank ("reviewedAt", To_String (Att.Reviewed_At));
      W.Field_If_Non_Blank ("contentHash", To_String (Att.Content_Hash));
      W.Object_End;
   end Write;

end Fusa.Attestation;
