path=r"C:\Users\Joseph Santander\AppData\Local\Pub\Cache\hosted\pub.dev\flutter_inappwebview-5.8.0\android\build.gradle"
f=open(path,"r",encoding="utf-8")
c=f.read()
f.close()
c=c.replace("depfaultConfig","defaultConfig")
f=open(path,"w",encoding="utf-8")
f.write(c)
f.close()
print("done")
