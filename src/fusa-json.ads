--  Minimal, dependency-free JSON reader used to parse .fusa.json and
--  .fusa-reqs.json. Writing is handled separately by Fusa.Json.Writer
--  (a streaming builder, not a tree serialiser).
--
--  Value trees are built with access types and are never explicitly freed:
--  ada-FuSa is a short-lived CLI process, and the OS reclaims the heap on
--  exit, matching the "no explicit finalization needed" tradeoff other
--  x-FuSa tools' hand-rolled JSON readers make for the same reason.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Vectors;

package Fusa.Json is

   Json_Error : exception;

   type Value_Kind is
     (Json_Null, Json_Bool, Json_Number, Json_String, Json_Array, Json_Object);

   type Value (Kind : Value_Kind := Json_Null);
   type Value_Access is access Value;

   package Value_Vectors is new Ada.Containers.Vectors (Positive, Value_Access);

   type Member is record
      Key : Unbounded_String;
      Val : Value_Access;
   end record;

   package Member_Vectors is new Ada.Containers.Vectors (Positive, Member);

   type Value (Kind : Value_Kind := Json_Null) is record
      case Kind is
         when Json_Null =>
            null;
         when Json_Bool =>
            Bool_Val : Boolean;
         when Json_Number =>
            Num_Val : Long_Float;
         when Json_String =>
            Str_Val : Unbounded_String;
         when Json_Array =>
            Items : Value_Vectors.Vector;
         when Json_Object =>
            Members : Member_Vectors.Vector;
      end case;
   end record;

   --  Parses Text as a single JSON document. Raises Json_Error with a
   --  human-readable message (including a 1-based character position) on
   --  malformed input.
   function Parse (Text : String) return Value_Access;

   --  ── Fail-safe accessors (mirror java-FuSa's Json.str/obj/arr helpers) ──
   --  All accessors treat a null V, a V of the wrong Kind, or a missing Key
   --  as "absent" and return the supplied default rather than raising.

   function Is_Object (V : Value_Access) return Boolean;
   function Is_Array  (V : Value_Access) return Boolean;

   function Has_Key (V : Value_Access; Key : String) return Boolean;

   --  Returns the member's value, or null if V is not an object or Key is
   --  absent.
   function Get_Member (V : Value_Access; Key : String) return Value_Access;

   function Get_String
     (V : Value_Access; Key : String; Default : String := "") return String;

   function Get_Bool
     (V : Value_Access; Key : String; Default : Boolean := False) return Boolean;

   --  Returns the array member for Key, or null if absent / not an array.
   function Get_Array (V : Value_Access; Key : String) return Value_Access;

   function Array_Length (V : Value_Access) return Natural;
   --  V must be a non-null Json_Array value (see Get_Array).
   function Array_Item (V : Value_Access; Index : Positive) return Value_Access;

   --  Direct (non-Key-mediated) string extraction, e.g. for array elements.
   function As_String (V : Value_Access; Default : String := "") return String;

end Fusa.Json;
