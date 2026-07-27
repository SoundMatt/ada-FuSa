with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Fusa.Json is

   procedure Expect (S : String; Pos : in out Positive; Ch : Character);
   procedure Skip_Ws (S : String; Pos : in out Positive);
   function Parse_Value (S : String; Pos : in out Positive) return Value_Access;
   function Parse_Object (S : String; Pos : in out Positive) return Value_Access;
   function Parse_Array (S : String; Pos : in out Positive) return Value_Access;
   function Parse_String_Literal
     (S : String; Pos : in out Positive) return Unbounded_String;
   function Parse_Number (S : String; Pos : in out Positive) return Value_Access;
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

   procedure Append_Utf8 (Result : in out Unbounded_String; Code : Natural) is
   begin
      if Code <= 16#7F# then
         Append (Result, Character'Val (Code));
      elsif Code <= 16#7FF# then
         Append (Result, Character'Val (16#C0# + Code / 64));
         Append (Result, Character'Val (16#80# + Code mod 64));
      else
         Append (Result, Character'Val (16#E0# + Code / 4096));
         Append (Result, Character'Val (16#80# + (Code / 64) mod 64));
         Append (Result, Character'Val (16#80# + Code mod 64));
      end if;
   end Append_Utf8;

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
                     if Pos + 3 > S'Last then
                        raise Json_Error with "invalid \u escape";
                     end if;
                     declare
                        Code : Natural := 0;
                     begin
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
                        Append_Utf8 (Result, Code);
                     end;
                  when others =>
                     raise Json_Error with "invalid escape character";
               end case;
            else
               Append (Result, C);
               Pos := Pos + 1;
            end if;
         end;
      end loop;
      return Result;
   end Parse_String_Literal;

   function Parse_Number (S : String; Pos : in out Positive) return Value_Access is
      Start : constant Positive := Pos;
   begin
      if Pos <= S'Last and then S (Pos) = '-' then
         Pos := Pos + 1;
      end if;
      if Pos > S'Last or else S (Pos) not in '0' .. '9' then
         raise Json_Error with "invalid number at position" & Positive'Image (Pos);
      end if;
      while Pos <= S'Last and then S (Pos) in '0' .. '9' loop
         Pos := Pos + 1;
      end loop;
      if Pos <= S'Last and then S (Pos) = '.' then
         Pos := Pos + 1;
         while Pos <= S'Last and then S (Pos) in '0' .. '9' loop
            Pos := Pos + 1;
         end loop;
      end if;
      if Pos <= S'Last and then (S (Pos) = 'e' or else S (Pos) = 'E') then
         Pos := Pos + 1;
         if Pos <= S'Last and then (S (Pos) = '+' or else S (Pos) = '-') then
            Pos := Pos + 1;
         end if;
         while Pos <= S'Last and then S (Pos) in '0' .. '9' loop
            Pos := Pos + 1;
         end loop;
      end if;
      declare
         V : constant Value_Access := new Value (Json_Number);
      begin
         V.Num_Val := Long_Float'Value (S (Start .. Pos - 1));
         return V;
      end;
   end Parse_Number;

   function Parse_Object (S : String; Pos : in out Positive) return Value_Access is
      V : constant Value_Access := new Value (Json_Object);
   begin
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
               Val : constant Value_Access := Parse_Value (S, Pos);
            begin
               V.Members.Append (Member'(Key => Key, Val => Val));
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

   function Parse_Array (S : String; Pos : in out Positive) return Value_Access is
      V : constant Value_Access := new Value (Json_Array);
   begin
      Expect (S, Pos, '[');
      Skip_Ws (S, Pos);
      if Pos <= S'Last and then S (Pos) = ']' then
         Pos := Pos + 1;
         return V;
      end if;
      loop
         Skip_Ws (S, Pos);
         declare
            Item : constant Value_Access := Parse_Value (S, Pos);
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

   function Parse_Value (S : String; Pos : in out Positive) return Value_Access is
   begin
      if Pos > S'Last then
         raise Json_Error with "unexpected end of input";
      end if;
      case S (Pos) is
         when '{' =>
            return Parse_Object (S, Pos);
         when '[' =>
            return Parse_Array (S, Pos);
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
      V := Parse_Value (Text, Pos);
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
