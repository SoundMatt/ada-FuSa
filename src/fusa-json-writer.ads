--  Streaming JSON output builder (not a tree serialiser). Every ada-FuSa
--  command builds its JSON output by calling Object_Start/Key/Value/...
--  in document order, mirroring java-FuSa's internal Json.Writer.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Fusa.Json.Writer is

   Max_Depth : constant := 32;

   --  Raised on caller protocol misuse: Object_End/Array_End with nothing
   --  open, Object_End/Array_End that doesn't match the innermost open
   --  container's kind, a value written inside an object with no
   --  preceding Key(), two Key() calls in a row, or nesting beyond
   --  Max_Depth. Every real call site in this codebase is statically
   --  well-formed, so this should never fire outside of a future
   --  programming error -- it exists so such an error fails loudly with a
   --  clear diagnostic instead of silently emitting corrupt JSON or
   --  crashing with a raw CONSTRAINT_ERROR.
   Writer_Error : exception;

   type Instance is tagged limited private;

   --  fusa:req REQ-025
   procedure Object_Start (W : in out Instance);
   --  fusa:req REQ-025
   procedure Object_End   (W : in out Instance);
   --  fusa:req REQ-025
   procedure Array_Start  (W : in out Instance);
   --  fusa:req REQ-025
   procedure Array_End    (W : in out Instance);

   --  Writes `"key": ` inside the currently-open object; the next call
   --  (Value/Object_Start/Array_Start/Null_Value) supplies the value.
   --  fusa:req REQ-026
   procedure Key (W : in out Instance; K : String);

   --  fusa:req REQ-027
   procedure Value      (W : in out Instance; S : String);
   --  fusa:req REQ-027
   procedure Value      (W : in out Instance; N : Integer);
   --  fusa:req REQ-027
   procedure Value      (W : in out Instance; B : Boolean);
   --  fusa:req REQ-028
   procedure Null_Value  (W : in out Instance);

   --  Convenience: Key (W, K); Value (W, V);
   --  fusa:req REQ-029
   procedure Field (W : in out Instance; K, V : String);
   --  fusa:req REQ-029
   procedure Field (W : in out Instance; K : String; V : Integer);
   --  fusa:req REQ-029
   procedure Field (W : in out Instance; K : String; V : Boolean);

   --  Field (W, K, V) is skipped entirely (no key/value written) when V
   --  is blank -- used for MAY string fields the spec says to omit rather
   --  than emit empty (e.g. asil/sil/dal, clause, standard).
   --  fusa:req REQ-030
   procedure Field_If_Non_Blank (W : in out Instance; K, V : String);

   --  fusa:req REQ-031
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
