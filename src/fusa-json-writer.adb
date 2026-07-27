with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Strings.Fixed;

package body Fusa.Json.Writer is

   Hex_Chars : constant String := "0123456789abcdef";

   function Quote (S : String) return String is
      Result : Unbounded_String := Null_Unbounded_String;
   begin
      Append (Result, '"');
      for C of S loop
         case C is
            when '"' =>
               Append (Result, "\""");
            when '\' =>
               Append (Result, "\\");
            when ASCII.LF =>
               Append (Result, "\n");
            when ASCII.CR =>
               Append (Result, "\r");
            when ASCII.HT =>
               Append (Result, "\t");
            when others =>
               if Character'Pos (C) < 16#20# then
                  Append (Result, "\u00");
                  Append (Result, Hex_Chars (Character'Pos (C) / 16 + 1));
                  Append (Result, Hex_Chars (Character'Pos (C) mod 16 + 1));
               else
                  Append (Result, C);
               end if;
         end case;
      end loop;
      Append (Result, '"');
      return To_String (Result);
   end Quote;

   procedure New_Line_Indent (W : in out Instance) is
   begin
      Append (W.Buf, ASCII.LF);
      for I in 1 .. W.Depth loop
         Append (W.Buf, "  ");
      end loop;
   end New_Line_Indent;

   --  Called immediately before writing any member/element/value. Handles
   --  comma placement between siblings and suppresses itself for the value
   --  half of a Key/Value pair (see Key below).
   procedure Before_Item (W : in out Instance) is
   begin
      if W.Awaiting_Value then
         W.Awaiting_Value := False;
         return;
      end if;
      if W.Depth = 0 then
         return;
      end if;
      if not W.Stack (W.Depth).First then
         Append (W.Buf, ",");
      end if;
      W.Stack (W.Depth).First := False;
      New_Line_Indent (W);
   end Before_Item;

   procedure Object_Start (W : in out Instance) is
   begin
      Before_Item (W);
      Append (W.Buf, "{");
      W.Depth := W.Depth + 1;
      W.Stack (W.Depth) := (Kind => In_Object, First => True);
   end Object_Start;

   procedure Object_End (W : in out Instance) is
      Was_Empty : constant Boolean := W.Stack (W.Depth).First;
   begin
      W.Depth := W.Depth - 1;
      if not Was_Empty then
         New_Line_Indent (W);
      end if;
      Append (W.Buf, "}");
   end Object_End;

   procedure Array_Start (W : in out Instance) is
   begin
      Before_Item (W);
      Append (W.Buf, "[");
      W.Depth := W.Depth + 1;
      W.Stack (W.Depth) := (Kind => In_Array, First => True);
   end Array_Start;

   procedure Array_End (W : in out Instance) is
      Was_Empty : constant Boolean := W.Stack (W.Depth).First;
   begin
      W.Depth := W.Depth - 1;
      if not Was_Empty then
         New_Line_Indent (W);
      end if;
      Append (W.Buf, "]");
   end Array_End;

   procedure Key (W : in out Instance; K : String) is
   begin
      Before_Item (W);
      Append (W.Buf, Quote (K));
      Append (W.Buf, ": ");
      W.Awaiting_Value := True;
   end Key;

   procedure Value (W : in out Instance; S : String) is
   begin
      Before_Item (W);
      Append (W.Buf, Quote (S));
   end Value;

   procedure Value (W : in out Instance; N : Integer) is
   begin
      Before_Item (W);
      Append (W.Buf, Ada.Strings.Fixed.Trim (Integer'Image (N), Ada.Strings.Left));
   end Value;

   procedure Value (W : in out Instance; B : Boolean) is
   begin
      Before_Item (W);
      Append (W.Buf, (if B then "true" else "false"));
   end Value;

   procedure Null_Value (W : in out Instance) is
   begin
      Before_Item (W);
      Append (W.Buf, "null");
   end Null_Value;

   procedure Field (W : in out Instance; K, V : String) is
   begin
      Key (W, K);
      Value (W, V);
   end Field;

   procedure Field (W : in out Instance; K : String; V : Integer) is
   begin
      Key (W, K);
      Value (W, V);
   end Field;

   procedure Field (W : in out Instance; K : String; V : Boolean) is
   begin
      Key (W, K);
      Value (W, V);
   end Field;

   procedure Field_If_Non_Blank (W : in out Instance; K, V : String) is
   begin
      if V'Length > 0 then
         Field (W, K, V);
      end if;
   end Field_If_Non_Blank;

   function To_String (W : Instance) return String is
   begin
      return To_String (W.Buf);
   end To_String;

end Fusa.Json.Writer;
