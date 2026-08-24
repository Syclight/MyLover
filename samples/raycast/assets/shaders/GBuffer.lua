return [[
    extern Image mainTex;
    extern float currentDepth;
    
    void effect() {
        vec4 texcolor = Texel(mainTex, VaryingTexCoord.xy);
        if (texcolor.a < 0.1) discard; 
        
        love_Canvases[0] = texcolor * VaryingColor;
        love_Canvases[1] = vec4(currentDepth, 0.0, 0.0, 1.0);
    }
]]