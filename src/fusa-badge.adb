with Ada.Strings.Fixed;

package body Fusa.Badge is

   function Trim_Img (N : Integer) return String is
     (Ada.Strings.Fixed.Trim (Integer'Image (N), Ada.Strings.Left));

   function Escape (S : String) return String is
      Buf : Unbounded_String := Null_Unbounded_String;
   begin
      for C of S loop
         case C is
            when '&' => Append (Buf, "&amp;");
            when '<' => Append (Buf, "&lt;");
            when '>' => Append (Buf, "&gt;");
            when '"' => Append (Buf, "&quot;");
            when others => Append (Buf, C);
         end case;
      end loop;
      return To_String (Buf);
   end Escape;

   --  No real font metrics are available without an external library or a
   --  system font-shaping call; 7px/character plus 10px of padding on each
   --  side is a common flat-badge approximation for an 11px sans-serif
   --  font and is close enough for a status badge (not a design asset).
   function Text_Width (S : String) return Natural is
     (S'Length * 7 + 10);

   function Render_Svg (Label, Message, Color : String) return String is
      Label_Width   : constant Natural := Text_Width (Label);
      Message_Width : constant Natural := Text_Width (Message);
      Total_Width   : constant Natural := Label_Width + Message_Width;
      Label_Mid     : constant Natural := Label_Width / 2;
      Message_Mid   : constant Natural := Label_Width + Message_Width / 2;
   begin
      return
        "<svg xmlns=""http://www.w3.org/2000/svg"" width=""" & Trim_Img (Total_Width) &
        """ height=""20"" role=""img"" aria-label=""" &
        Escape (Label) & ": " & Escape (Message) & """>" & ASCII.LF &
        "<mask id=""m""><rect width=""" & Trim_Img (Total_Width) &
        """ height=""20"" rx=""3"" fill=""#fff""/></mask>" & ASCII.LF &
        "<g mask=""url(#m)"">" & ASCII.LF &
        "<rect width=""" & Trim_Img (Label_Width) & """ height=""20"" fill=""#555""/>" & ASCII.LF &
        "<rect x=""" & Trim_Img (Label_Width) & """ width=""" & Trim_Img (Message_Width) &
        """ height=""20"" fill=""" & Escape (Color) & """/>" & ASCII.LF &
        "</g>" & ASCII.LF &
        "<g fill=""#fff"" text-anchor=""middle"" " &
        "font-family=""Verdana,Geneva,sans-serif"" font-size=""11"">" & ASCII.LF &
        "<text x=""" & Trim_Img (Label_Mid) & """ y=""14"">" & Escape (Label) & "</text>" & ASCII.LF &
        "<text x=""" & Trim_Img (Message_Mid) & """ y=""14"">" & Escape (Message) & "</text>" & ASCII.LF &
        "</g>" & ASCII.LF &
        "</svg>" & ASCII.LF;
   end Render_Svg;

end Fusa.Badge;
