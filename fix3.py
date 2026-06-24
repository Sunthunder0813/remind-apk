import re
path=r"C:\Users\Joseph Santander\AppData\Local\Pub\Cache\hosted\pub.dev\youtube_player_iframe-6.0.2\lib\src\controller\js_bridge.dart"
f=open(path,"r",encoding="utf-8")
c=f.read()
f.close()
c=c.replace("Duration(seconds: 30)","Duration(seconds: 120)")
f=open(path,"w",encoding="utf-8")
f.write(c)
f.close()
print("done")
