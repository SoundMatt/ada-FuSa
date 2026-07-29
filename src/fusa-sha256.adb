with Interfaces; use Interfaces;

package body Fusa.Sha256 is

   pragma SPARK_Mode (On);

   subtype Word is Unsigned_32;

   type Word_Array is array (Natural range <>) of Word;
   type Byte_Array is array (Natural range <>) of Unsigned_8;

   K : constant Word_Array (0 .. 63) :=
     (16#428a2f98#, 16#71374491#, 16#b5c0fbcf#, 16#e9b5dba5#,
      16#3956c25b#, 16#59f111f1#, 16#923f82a4#, 16#ab1c5ed5#,
      16#d807aa98#, 16#12835b01#, 16#243185be#, 16#550c7dc3#,
      16#72be5d74#, 16#80deb1fe#, 16#9bdc06a7#, 16#c19bf174#,
      16#e49b69c1#, 16#efbe4786#, 16#0fc19dc6#, 16#240ca1cc#,
      16#2de92c6f#, 16#4a7484aa#, 16#5cb0a9dc#, 16#76f988da#,
      16#983e5152#, 16#a831c66d#, 16#b00327c8#, 16#bf597fc7#,
      16#c6e00bf3#, 16#d5a79147#, 16#06ca6351#, 16#14292967#,
      16#27b70a85#, 16#2e1b2138#, 16#4d2c6dfc#, 16#53380d13#,
      16#650a7354#, 16#766a0abb#, 16#81c2c92e#, 16#92722c85#,
      16#a2bfe8a1#, 16#a81a664b#, 16#c24b8b70#, 16#c76c51a3#,
      16#d192e819#, 16#d6990624#, 16#f40e3585#, 16#106aa070#,
      16#19a4c116#, 16#1e376c08#, 16#2748774c#, 16#34b0bcb5#,
      16#391c0cb3#, 16#4ed8aa4a#, 16#5b9cca4f#, 16#682e6ff3#,
      16#748f82ee#, 16#78a5636f#, 16#84c87814#, 16#8cc70208#,
      16#90befffa#, 16#a4506ceb#, 16#bef9a3f7#, 16#c67178f2#);

   Hex_Chars : constant String := "0123456789abcdef";

   function Hex_Digest (Data : String) return String is

      H : Word_Array (0 .. 7) :=
        (16#6a09e667#, 16#bb67ae85#, 16#3c6ef372#, 16#a54ff53a#,
         16#510e527f#, 16#9b05688c#, 16#1f83d9ab#, 16#5be0cd19#);

      Bit_Len      : constant Unsigned_64 :=
        Unsigned_64 (Data'Length) * 8;
      Pad_Zeros    : Natural;
      Padded_Len   : Natural;
   begin
      --  §Padding: message || 0x80 || zeros || 64-bit big-endian bit length,
      --  total length a multiple of 64 bytes.
      declare
         Rem64 : constant Natural := (Data'Length + 1) mod 64;
      begin
         Pad_Zeros := (if Rem64 <= 56 then 56 - Rem64 else 120 - Rem64);
      end;
      Padded_Len := Data'Length + 1 + Pad_Zeros + 8;

      declare
         Msg : Byte_Array (0 .. Padded_Len - 1);
      begin
         for I in Data'Range loop
            Msg (I - Data'First) := Character'Pos (Data (I));
         end loop;
         Msg (Data'Length) := 16#80#;
         for I in Data'Length + 1 .. Padded_Len - 9 loop
            Msg (I) := 0;
         end loop;
         for B in 0 .. 7 loop
            Msg (Padded_Len - 1 - B) :=
              Unsigned_8 (Shift_Right (Bit_Len, B * 8) and 16#FF#);
         end loop;

         --  Process each 64-byte chunk.
         declare
            Num_Chunks : constant Natural := Padded_Len / 64;
         begin
            for Chunk in 0 .. Num_Chunks - 1 loop
               declare
                  Base : constant Natural := Chunk * 64;
                  W    : Word_Array (0 .. 63);
                  A, Bv, C, D, E, F, G, Hh : Word;
                  S0, S1, Ch, Maj, T1, T2 : Word;
               begin
                  for T in 0 .. 15 loop
                     W (T) :=
                       Shift_Left (Word (Msg (Base + T * 4)), 24) or
                       Shift_Left (Word (Msg (Base + T * 4 + 1)), 16) or
                       Shift_Left (Word (Msg (Base + T * 4 + 2)), 8) or
                       Word (Msg (Base + T * 4 + 3));
                  end loop;
                  for T in 16 .. 63 loop
                     declare
                        S0e : constant Word :=
                          Rotate_Right (W (T - 15), 7) xor
                          Rotate_Right (W (T - 15), 18) xor
                          Shift_Right (W (T - 15), 3);
                        S1e : constant Word :=
                          Rotate_Right (W (T - 2), 17) xor
                          Rotate_Right (W (T - 2), 19) xor
                          Shift_Right (W (T - 2), 10);
                     begin
                        W (T) := W (T - 16) + S0e + W (T - 7) + S1e;
                     end;
                  end loop;

                  A := H (0); Bv := H (1); C := H (2); D := H (3);
                  E := H (4); F := H (5); G := H (6); Hh := H (7);

                  for T in 0 .. 63 loop
                     S1  := Rotate_Right (E, 6) xor Rotate_Right (E, 11)
                              xor Rotate_Right (E, 25);
                     Ch  := (E and F) xor ((not E) and G);
                     T1  := Hh + S1 + Ch + K (T) + W (T);
                     S0  := Rotate_Right (A, 2) xor Rotate_Right (A, 13)
                              xor Rotate_Right (A, 22);
                     Maj := (A and Bv) xor (A and C) xor (Bv and C);
                     T2  := S0 + Maj;
                     Hh := G; G := F; F := E; E := D + T1;
                     D := C; C := Bv; Bv := A; A := T1 + T2;
                  end loop;

                  H (0) := H (0) + A; H (1) := H (1) + Bv;
                  H (2) := H (2) + C; H (3) := H (3) + D;
                  H (4) := H (4) + E; H (5) := H (5) + F;
                  H (6) := H (6) + G; H (7) := H (7) + Hh;
               end;
            end loop;
         end;
      end;

      declare
         Result : String (1 .. 64);
      begin
         for I in 0 .. 7 loop
            for B in 0 .. 3 loop
               declare
                  Byte : constant Unsigned_8 :=
                    Unsigned_8 (Shift_Right (H (I), (3 - B) * 8) and 16#FF#);
                  Pos  : constant Natural := I * 8 + B * 2 + 1;
               begin
                  Result (Pos) :=
                    Hex_Chars (Natural (Shift_Right (Byte, 4)) + 1);
                  Result (Pos + 1) :=
                    Hex_Chars (Natural (Byte and 16#0F#) + 1);
               end;
            end loop;
         end loop;
         return Result;
      end;
   end Hex_Digest;

end Fusa.Sha256;
