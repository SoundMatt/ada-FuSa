with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Strings.Unbounded.Hash;
with Ada.Containers.Hashed_Maps;

package body Fusa.Json is

   --  Maps an object's member key to its index in Members, so a duplicate
   --  key during parsing can be found in O(1) rather than by rescanning
   --  every previously-parsed member -- an adversarial input with N
   --  identical (or merely unique-but-numerous) keys would otherwise cost
   --  O(N^2), a CPU-exhaustion DoS on any tool that feeds this parser
   --  untrusted JSON.
   package Key_Index_Maps is new Ada.Containers.Hashed_Maps
     (Key_Type        => Unbounded_String,
      Element_Type    => Positive,
      Hash            => Ada.Strings.Unbounded.Hash,
      Equivalent_Keys => "=");

   --  Recursion-depth bound: .fusa.json/.fusa-reqs.json are external files
   --  this tool reads, so a malformed or adversarial deeply-nested input
   --  must not be able to blow the stack (STORAGE_ERROR) -- it should
   --  raise the documented Json_Error instead.
   Max_Nesting_Depth : constant := 500;

   procedure Expect (S : String; Pos : in out Positive; Ch : Character);
   procedure Skip_Ws (S : String; Pos : in out Positive);
   function Parse_Value
     (S : String; Pos : in out Positive; Depth : Natural) return Value_Access;
   function Parse_Object
     (S : String; Pos : in out Positive; Depth : Natural) return Value_Access;
   function Parse_Array
     (S : String; Pos : in out Positive; Depth : Natural) return Value_Access;
   function Parse_String_Literal
     (S : String; Pos : in out Positive) return Unbounded_String;
   function Parse_Number (S : String; Pos : in out Positive) return Value_Access;
   function Parse_Hex4 (S : String; Pos : in out Positive) return Natural;
   procedure Append_Utf8 (Result : in out Unbounded_String; Code : Natural);

   ----------------------------------------------------------------------

   procedure Expect (S : String; Pos : in out Positive; Ch : Character) is
   begin
      if Pos > S'Last or else S (Pos) /= Ch then
         raise Json_Error with
           "expected '" & Ch & "' at position" & Positive'Image (Pos);
      end if;
      Pos := Pos + 1;
   end Expect;

   procedure Skip_Ws (S : String; Pos : in out Positive) is
   begin
      while Pos <= S'Last and then
        (S (Pos) = ' ' or else S (Pos) = ASCII.HT or else
         S (Pos) = ASCII.LF or else S (Pos) = ASCII.CR)
      loop
         Pos := Pos + 1;
      end loop;
   end Skip_Ws;

   --  §4.2's UTF-8 encoder, extended to the full Unicode range (4-byte
   --  sequences for codepoints above 0xFFFF, reachable once combined
   --  surrogate pairs are supported -- see Parse_String_Literal).
   procedure Append_Utf8 (Result : in out Unbounded_String; Code : Natural) is
   begin
      if Code <= 16#7F# then
         Append (Result, Character'Val (Code));
      elsif Code <= 16#7FF# then
         Append (Result, Character'Val (16#C0# + Code / 64));
         Append (Result, Character'Val (16#80# + Code mod 64));
      elsif Code <= 16#FFFF# then
         Append (Result, Character'Val (16#E0# + Code / 4096));
         Append (Result, Character'Val (16#80# + (Code / 64) mod 64));
         Append (Result, Character'Val (16#80# + Code mod 64));
      else
         Append (Result, Character'Val (16#F0# + Code / 262144));
         Append (Result, Character'Val (16#80# + (Code / 4096) mod 64));
         Append (Result, Character'Val (16#80# + (Code / 64) mod 64));
         Append (Result, Character'Val (16#80# + Code mod 64));
      end if;
   end Append_Utf8;

   --  Reads exactly 4 hex digits at Pos, advances Pos past them, and
   --  returns their value. Raises Json_Error on insufficient length or an
   --  invalid hex digit.
   function Parse_Hex4 (S : String; Pos : in out Positive) return Natural is
      Code : Natural := 0;
   begin
      if Pos + 3 > S'Last then
         raise Json_Error with "invalid \u escape";
      end if;
      for I in 0 .. 3 loop
         declare
            Hc : constant Character := S (Pos + I);
            D  : Natural;
         begin
            case Hc is
               when '0' .. '9' =>
                  D := Character'Pos (Hc) - Character'Pos ('0');
               when 'a' .. 'f' =>
                  D := Character'Pos (Hc) - Character'Pos ('a') + 10;
               when 'A' .. 'F' =>
                  D := Character'Pos (Hc) - Character'Pos ('A') + 10;
               when others =>
                  raise Json_Error with "invalid hex digit in \u escape";
            end case;
            Code := Code * 16 + D;
         end;
      end loop;
      Pos := Pos + 4;
      return Code;
   end Parse_Hex4;

   function Parse_String_Literal
     (S : String; Pos : in out Positive) return Unbounded_String
   is
      Result : Unbounded_String := Null_Unbounded_String;
   begin
      Expect (S, Pos, '"');
      loop
         if Pos > S'Last then
            raise Json_Error with "unterminated string literal";
         end if;

         declare
            C : constant Character := S (Pos);
         begin
            if C = '"' then
               Pos := Pos + 1;
               exit;

            elsif C = '\' then
               Pos := Pos + 1;
               if Pos > S'Last then
                  raise Json_Error with "unterminated escape sequence";
               end if;

               case S (Pos) is
                  when '"'    => Append (Result, '"');       Pos := Pos + 1;
                  when '\'    => Append (Result, '\');       Pos := Pos + 1;
                  when '/'    => Append (Result, '/');       Pos := Pos + 1;
                  when 'b'    => Append (Result, ASCII.BS);  Pos := Pos + 1;
                  when 'f'    => Append (Result, ASCII.FF);  Pos := Pos + 1;
                  when 'n'    => Append (Result, ASCII.LF);  Pos := Pos + 1;
                  when 'r'    => Append (Result, ASCII.CR);  Pos := Pos + 1;
                  when 't'    => Append (Result, ASCII.HT);  Pos := Pos + 1;
                  when 'u' =>
                     Pos := Pos + 1;
                     declare
                        Code : constant Natural := Parse_Hex4 (S, Pos);
                     begin
                        if Code in 16#D800# .. 16#DBFF# then
                           --  High surrogate: must be immediately followed
                           --  by a "\uXXXX" low surrogate to combine into
                           --  a single codepoint above the BMP. A lone,
                           --  unpaired surrogate can never be validly
                           --  represented in UTF-8, so it's rejected.
                           if Pos + 1 <= S'Last
                             and then S (Pos) = '\' and then S (Pos + 1) = 'u'
                           then
                              declare
                                 Low_Pos : Positive := Pos + 2;
                                 Low     : constant Natural := Parse_Hex4 (S, Low_Pos);
                              begin
                                 if Low in 16#DC00# .. 16#DFFF# then
                                    Pos := Low_Pos;
                                    Append_Utf8
                                      (Result,
                                       16#10000# +
                                         (Code - 16#D800#) * 16#400# +
                                         (Low - 16#DC00#));
                                 else
                                    raise Json_Error with
                                      "unpaired UTF-16 high surrogate in \u escape";
                                 end if;
                              end;
                           else
                              raise Json_Error with
                                "unpaired UTF-16 high surrogate in \u escape";
                           end if;
                        elsif Code in 16#DC00# .. 16#DFFF# then
                           raise Json_Error with
                             "unpaired UTF-16 low surrogate in \u escape";
                        else
                           Append_Utf8 (Result, Code);
                        end if;
                     end;
                  when others =>
                     raise Json_Error with "invalid escape character";
               end case;
            elsif Character'Pos (C) < 16#20# then
               --  RFC 8259 §7: control characters (U+0000-U+001F) MUST be
               --  escaped (e.g. as "\n") -- a literal, unescaped one
               --  is invalid JSON, not merely unusual input.
               raise Json_Error with
                 "unescaped control character in string literal at position"
                 & Positive'Image (Pos);
            else
               Append (Result, C);
               Pos := Pos + 1;
            end if;
         end;
      end loop;
      return Result;
   end Parse_String_Literal;

   --  RFC 8259 §6 number grammar: optional '-', an integer part that is
   --  either a single '0' or a nonzero digit followed by digits (a
   --  leading zero followed by more digits, e.g. "01", is invalid), an
   --  optional '.' fraction requiring at least one digit, and an optional
   --  'e'/'E' exponent requiring at least one digit (after an optional
   --  sign) -- "1e" / "1e+" / "1." are all rejected rather than handed to
   --  Long_Float'Value, which would raise an unguarded CONSTRAINT_ERROR.
   function Parse_Number (S : String; Pos : in out Positive) return Value_Access is
      Start : constant Positive := Pos;
   begin
      if Pos <= S'Last and then S (Pos) = '-' then
         Pos := Pos + 1;
      end if;
      if Pos > S'Last or else S (Pos) not in '0' .. '9' then
         raise Json_Error with "invalid number at position" & Positive'Image (Pos);
      end if;

      if S (Pos) = '0' then
         Pos := Pos + 1;
         if Pos <= S'Last and then S (Pos) in '0' .. '9' then
            raise Json_Error with
              "invalid number: leading zero at position" & Positive'Image (Pos);
         end if;
      else
         while Pos <= S'Last and then S (Pos) in '0' .. '9' loop
            Pos := Pos + 1;
         end loop;
      end if;

      if Pos <= S'Last and then S (Pos) = '.' then
         Pos := Pos + 1;
         if Pos > S'Last or else S (Pos) not in '0' .. '9' then
            raise Json_Error with
              "invalid number: expected digit after '.' at position" &
              Positive'Image (Pos);
         end if;
         while Pos <= S'Last and then S (Pos) in '0' .. '9' loop
            Pos := Pos + 1;
         end loop;
      end if;

      if Pos <= S'Last and then (S (Pos) = 'e' or else S (Pos) = 'E') then
         Pos := Pos + 1;
         if Pos <= S'Last and then (S (Pos) = '+' or else S (Pos) = '-') then
            Pos := Pos + 1;
         end if;
         if Pos > S'Last or else S (Pos) not in '0' .. '9' then
            raise Json_Error with
              "invalid number: expected digit in exponent at position" &
              Positive'Image (Pos);
         end if;
         while Pos <= S'Last and then S (Pos) in '0' .. '9' loop
            Pos := Pos + 1;
         end loop;
      end if;

      declare
         V : constant Value_Access := new Value (Json_Number);
      begin
         V.Num_Val := Long_Float'Value (S (Start .. Pos - 1));
         --  The grammar above rejects syntactically malformed numbers, but
         --  a syntactically valid one (e.g. "1e400") can still overflow
         --  Long_Float'Value's range -- GNAT returns IEEE +/-Infinity
         --  silently rather than raising, which would otherwise propagate
         --  a non-finite value into every downstream consumer (metrics,
         --  RPN scoring, coverage percentages) with no error at the point
         --  of parsing.
         if V.Num_Val > Long_Float'Last or else V.Num_Val < -Long_Float'Last then
            raise Json_Error with
              "number out of range at position" & Positive'Image (Start);
         end if;
         return V;
      end;
   end Parse_Number;

   function Parse_Object
     (S : String; Pos : in out Positive; Depth : Natural) return Value_Access
   is
      V         : constant Value_Access := new Value (Json_Object);
      Key_Index : Key_Index_Maps.Map;
   begin
      if Depth > Max_Nesting_Depth then
         raise Json_Error with "maximum nesting depth exceeded";
      end if;
      Expect (S, Pos, '{');
      Skip_Ws (S, Pos);
      if Pos <= S'Last and then S (Pos) = '}' then
         Pos := Pos + 1;
         return V;
      end if;
      loop
         Skip_Ws (S, Pos);
         declare
            Key : constant Unbounded_String := Parse_String_Literal (S, Pos);
         begin
            Skip_Ws (S, Pos);
            Expect (S, Pos, ':');
            Skip_Ws (S, Pos);
            declare
               Val : constant Value_Access := Parse_Value (S, Pos, Depth + 1);
            begin
               --  Last-value-wins on a duplicate key, matching common JSON
               --  tooling (JS JSON.parse, Python json, jq) rather than
               --  silently keeping both members.
               if Key_Index.Contains (Key) then
                  V.Members.Replace_Element
                    (Key_Index (Key), Member'(Key => Key, Val => Val));
               else
                  V.Members.Append (Member'(Key => Key, Val => Val));
                  Key_Index.Insert (Key, Natural (V.Members.Length));
               end if;
            end;
         end;
         Skip_Ws (S, Pos);
         if Pos <= S'Last and then S (Pos) = ',' then
            Pos := Pos + 1;
         elsif Pos <= S'Last and then S (Pos) = '}' then
            Pos := Pos + 1;
            exit;
         else
            raise Json_Error with
              "expected ',' or '}' at position" & Positive'Image (Pos);
         end if;
      end loop;
      return V;
   end Parse_Object;

   function Parse_Array
     (S : String; Pos : in out Positive; Depth : Natural) return Value_Access
   is
      V : constant Value_Access := new Value (Json_Array);
   begin
      if Depth > Max_Nesting_Depth then
         raise Json_Error with "maximum nesting depth exceeded";
      end if;
      Expect (S, Pos, '[');
      Skip_Ws (S, Pos);
      if Pos <= S'Last and then S (Pos) = ']' then
         Pos := Pos + 1;
         return V;
      end if;
      loop
         Skip_Ws (S, Pos);
         declare
            Item : constant Value_Access := Parse_Value (S, Pos, Depth + 1);
         begin
            V.Items.Append (Item);
         end;
         Skip_Ws (S, Pos);
         if Pos <= S'Last and then S (Pos) = ',' then
            Pos := Pos + 1;
         elsif Pos <= S'Last and then S (Pos) = ']' then
            Pos := Pos + 1;
            exit;
         else
            raise Json_Error with
              "expected ',' or ']' at position" & Positive'Image (Pos);
         end if;
      end loop;
      return V;
   end Parse_Array;

   function Parse_Value
     (S : String; Pos : in out Positive; Depth : Natural) return Value_Access
   is
   begin
      if Pos > S'Last then
         raise Json_Error with "unexpected end of input";
      end if;
      case S (Pos) is
         when '{' =>
            return Parse_Object (S, Pos, Depth);
         when '[' =>
            return Parse_Array (S, Pos, Depth);
         when '"' =>
            declare
               V : constant Value_Access := new Value (Json_String);
            begin
               V.Str_Val := Parse_String_Literal (S, Pos);
               return V;
            end;
         when 't' =>
            if Pos + 3 <= S'Last and then S (Pos .. Pos + 3) = "true" then
               Pos := Pos + 4;
               declare
                  V : constant Value_Access := new Value (Json_Bool);
               begin
                  V.Bool_Val := True;
                  return V;
               end;
            end if;
            raise Json_Error with "invalid literal at position" & Positive'Image (Pos);
         when 'f' =>
            if Pos + 4 <= S'Last and then S (Pos .. Pos + 4) = "false" then
               Pos := Pos + 5;
               declare
                  V : constant Value_Access := new Value (Json_Bool);
               begin
                  V.Bool_Val := False;
                  return V;
               end;
            end if;
            raise Json_Error with "invalid literal at position" & Positive'Image (Pos);
         when 'n' =>
            if Pos + 3 <= S'Last and then S (Pos .. Pos + 3) = "null" then
               Pos := Pos + 4;
               return new Value (Json_Null);
            end if;
            raise Json_Error with "invalid literal at position" & Positive'Image (Pos);
         when '-' | '0' .. '9' =>
            return Parse_Number (S, Pos);
         when others =>
            raise Json_Error with
              "unexpected character at position" & Positive'Image (Pos);
      end case;
   end Parse_Value;

   function Parse (Text : String) return Value_Access is
      Pos : Positive;
      V   : Value_Access;
   begin
      if Text'Length = 0 then
         raise Json_Error with "empty input";
      end if;
      Pos := Text'First;
      Skip_Ws (Text, Pos);
      V := Parse_Value (Text, Pos, 0);
      Skip_Ws (Text, Pos);
      if Pos <= Text'Last then
         raise Json_Error with "trailing data at position" & Positive'Image (Pos);
      end if;
      return V;
   end Parse;

   ----------------------------------------------------------------------
   --  Accessors
   ----------------------------------------------------------------------

   function Is_Object (V : Value_Access) return Boolean is
     (V /= null and then V.Kind = Json_Object);

   function Is_Array (V : Value_Access) return Boolean is
     (V /= null and then V.Kind = Json_Array);

   function Get_Member (V : Value_Access; Key : String) return Value_Access is
   begin
      if V = null or else V.Kind /= Json_Object then
         return null;
      end if;
      for M of V.Members loop
         if To_String (M.Key) = Key then
            return M.Val;
         end if;
      end loop;
      return null;
   end Get_Member;

   function Has_Key (V : Value_Access; Key : String) return Boolean is
     (Get_Member (V, Key) /= null);

   function As_String (V : Value_Access; Default : String := "") return String is
   begin
      if V /= null and then V.Kind = Json_String then
         return To_String (V.Str_Val);
      end if;
      return Default;
   end As_String;

   function Get_String
     (V : Value_Access; Key : String; Default : String := "") return String is
     (As_String (Get_Member (V, Key), Default));

   function Get_Bool
     (V : Value_Access; Key : String; Default : Boolean := False) return Boolean
   is
      M : constant Value_Access := Get_Member (V, Key);
   begin
      if M /= null and then M.Kind = Json_Bool then
         return M.Bool_Val;
      end if;
      return Default;
   end Get_Bool;

   function Get_Array (V : Value_Access; Key : String) return Value_Access is
      M : constant Value_Access := Get_Member (V, Key);
   begin
      if M /= null and then M.Kind = Json_Array then
         return M;
      end if;
      return null;
   end Get_Array;

   function Array_Length (V : Value_Access) return Natural is
     (if V /= null and then V.Kind = Json_Array
      then Natural (V.Items.Length) else 0);

   function Array_Item (V : Value_Access; Index : Positive) return Value_Access is
     (V.Items.Element (Index));

end Fusa.Json;
