# Erzeugt Assets/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png (Pillow). Entwurf "FP aus Terminblöcken", 24.09.2026.
from PIL import Image, ImageDraw, ImageFilter, ImageChops
S=4; W=1024*S
def sc(v): return v*S
def bg():
    img=Image.new("RGB",(W,W)); d=ImageDraw.Draw(img)
    for y in range(W):
        t=y/W
        d.line([(0,y),(W,y)],fill=(int(0x22+(0x0A-0x22)*t),int(0x32+(0x10-0x32)*t),int(0x5E+(0x26-0x5E)*t)))
    glow=Image.new("L",(W,W),0); ImageDraw.Draw(glow).ellipse([sc(-250),sc(-300),sc(650),sc(520)],fill=80)
    glow=glow.filter(ImageFilter.GaussianBlur(sc(130)))
    return Image.composite(Image.new("RGB",(W,W),(0x5F,0x80,0xE0)),img,glow)
def blank(): return Image.new("L",(W,W),0)
def put(img,m,color):
    sh=m.filter(ImageFilter.GaussianBlur(sc(12))).point(lambda v:int(v*0.5))
    img.paste((4,8,20),(0,int(sc(10))),sh); img.paste(color,(0,0),m)
def capsule(m,x0,y0,x1,y1):
    r=min(x1-x0,y1-y0)/2
    ImageDraw.Draw(m).rounded_rectangle([sc(x0),sc(y0),sc(x1),sc(y1)],radius=sc(r),fill=255); return m

T=88; G=20; R=112
top,bot=270,754
# Gesamtbreite: F-Stamm .. P-Bogen-Außenkante
fw=T+G+196; gap_fp=64
pw=T+G+(T/2)+70+R+T/2
total=fw+gap_fp+pw
ox=(1024-total)/2
img=bg()
fx=ox
put(img,capsule(blank(),fx,top,fx+T,bot),(0x6E,0x9B,0xFF))
put(img,capsule(blank(),fx+T+G,top,fx+T+G+196,top+T),(0x4F,0xD3,0xA0))
put(img,capsule(blank(),fx+T+G,top+206,fx+T+G+146,top+206+T),(0xFF,0xB4,0x54))
px=fx+fw+gap_fp
put(img,capsule(blank(),px,top,px+T,bot),(0xFF,0x87,0x97))
# P-Bogen: zwei Geraden + Halbring
x0=px+T+G; cx=x0+T/2+70; yc=top+T/2+R
bowl=blank(); d=ImageDraw.Draw(bowl)
ring=blank(); ImageDraw.Draw(ring).ellipse([sc(cx-R-T/2),sc(yc-R-T/2),sc(cx+R+T/2),sc(yc+R+T/2)],fill=255)
hole=blank(); ImageDraw.Draw(hole).ellipse([sc(cx-R+T/2),sc(yc-R+T/2),sc(cx+R-T/2),sc(yc+R-T/2)],fill=255)
ring=ImageChops.subtract(ring,hole)
half=blank(); ImageDraw.Draw(half).rectangle([sc(cx),0,W,W],fill=255)
ring=ImageChops.multiply(ring,half)
bowl=ImageChops.lighter(bowl,ring)
d=ImageDraw.Draw(bowl)
for yy in (top, yc+R-T/2):
    d.ellipse([sc(x0),sc(yy),sc(x0+T),sc(yy+T)],fill=255)       # runde linke Kappe
    d.rectangle([sc(x0+T/2),sc(yy),sc(cx+1),sc(yy+T)],fill=255)  # Gerade bis zum Ring
put(img,bowl,(0xC4,0x9B,0xFF))
out=img.resize((1024,1024),Image.LANCZOS); out.save("Assets/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
print(ox, px+T+G+T/2+70+R+T/2)
