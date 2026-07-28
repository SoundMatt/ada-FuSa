--  Minimal, dependency-free SVG status-badge rendering (shields.io "flat"
--  style: two colour blocks side by side, label on the left, message on
--  the right) for the `badge` command.

package Fusa.Badge is

   --  Renders a self-contained SVG document. Text width is estimated from
   --  character count (no real font metrics available without an external
   --  library), using the same per-character advance shields.io's own flat
   --  template assumes for its default 11px Verdana-ish font stack.
   --  fusa:req REQ-098
   function Render_Svg (Label, Message, Color : String) return String;

end Fusa.Badge;
