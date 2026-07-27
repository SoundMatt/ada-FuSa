--  Streaming JSON output builder (not a tree serialiser). Every ada-FuSa
--  command builds its JSON output by calling Object_Start/Key/Value/...
--  in document order, mirroring java-FuSa's internal Json.Writer.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Fusa.Json.Writer is

   Max_Depth : constant := 32;

   type Instance is tagged limited private;

   procedure Object_Start (W : in out Instance);
   procedure Object_End   (W : in out Instance);
   procedure Array_Start  (W : in out Instance);
   procedure Array_End    (W : in out Instance);

   --  Writes `"key": ` inside the currently-open object; the next call
   --  (Value/Object_Start/Array_Start/Null_Value) supplies the value.
   procedure Key (W : in out Instance; K : String);

   procedure Value      (W : in out Instance; S : String);
   procedure Value      (W : in out Instance; N : Integer);
   procedure Value      (W : in out Instance; B : Boolean);
   procedure Null_Value  (W : in out Instance);

   --  Convenience: Key (W, K); Value (W, V);
   procedure Field (W : in out Instance; K, V : String);
   procedure Field (W : in out Instance; K : String; V : Integer);
   procedure Field (W : in out Instance; K : String; V : Boolean);

   --  Field (W, K, V) is skipped entirely (no key/value written) when V
   --  is blank -- used for MAY string fields the spec says to omit rather
   --  than emit empty (e.g. asil/sil/dal, clause, standard).
   procedure Field_If_Non_Blank (W : in out Instance; K, V : String);

   function To_String (W : Instance) return String;

private

   type Container_Kind is (In_Object, In_Array);

   type Frame is record
      Kind  : Container_Kind := In_Object;
      First : Boolean := True;
   end record;

   type Frame_Array is array (1 .. Max_Depth) of Frame;

   type Instance is tagged limited record
      Buf            : Unbounded_String := Null_Unbounded_String;
      Stack          : Frame_Array;
      Depth          : Natural := 0;
      Awaiting_Value : Boolean := False;
   end record;

end Fusa.Json.Writer;
