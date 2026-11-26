#!/bin/sh
# Print the PMIC power-on/reset log (PMK8850 SDAMs 0x7400-0x75FF) of the UX3407NA.
# Read-only. Shows why the last ~7 power-ons/resets happened (power key, PS_HOLD, UVLO, over-temp, ...).
# The log has no timestamps; the last entries are the most recent boot. A normal reboot also shows
# "PS_HOLD / HARD_RESET", so compare with `journalctl --list-boots` to tell crashes from reboots.
# Layout from Qualcomm's downstream drivers/soc/qcom/pmic-pon-log.c.
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
F=/sys/kernel/debug/regmap/0-00/registers
[ -r "$F" ] || { echo "no $F (debugfs not mounted, or the PMIC regmap has another name)"; exit 1; }
exec python3 -I - "$F" <<'PY'
import sys
f=open(sys.argv[1],'rb'); w=len(f.readline()); r={}
for base in (0x7400,0x7500):
    f.seek(base*w)
    for _ in range(0x100):
        a,v=f.readline().decode().split(':'); r[int(a,16)]=int(v,16)
SDAMS=[0x7400,0x7500]; START,END=0x4B,0xBF; FS=END-START+1
cnt=r[SDAMS[0]+0x45]+1; ptr=r[SDAMS[0]+0x46]; sn=r[SDAMS[0]+0x47]
fifo=[]
for s in SDAMS[:cnt]: fifo += [r[s+a] for a in range(START,END+1)]
tot=FS*cnt; maxe=tot//4; end=sn*FS+ptr-START; st=(end-maxe*4)%tot
STATE=["FAULT","PON","POFF","ON","RESET","OFF","FAULT","WARM_RESET"]
F1=["GP_FAULT0","GP_FAULT1","GP_FAULT2","GP_FAULT3","MBG_FAULT","OVLO","UVLO","AVDD_RB"]
F2=["?0","?1","?2","FAULT_N","FAULT_WATCHDOG","PBS_NACK","RESTART_PON","OVERTEMP_STAGE3"]
F3=["GP_FAULT%d"%i for i in range(4,12)]
S3=["?0","?1","?2","?3","FAULT_N","FAULT_WATCHDOG","PBS_NACK","KPDPWR_AND/OR_RESIN"]
PBL=["?0","?1","?2","?3","?4","?5","XVDD","DVDD"]
PON={0x84:"PS_HOLD",0x85:"HARD_RESET",0x86:"RESIN_N",0x87:"KPDPWR_N (power key)",0x202:"USB_CHARGER",0x621:"RTC_ALARM",0x640:"SMPL (sudden power loss)",0x31C2:"USB_CHARGER",0x71C2:"USB_CHARGER"}
RST={0x80:"KPDPWR_N_S2 (power key held)",0x81:"RESIN_N_S2",0x82:"KPDPWR_N_AND_RESIN_N_S2",0x83:"PMIC_WATCHDOG_S2",0x84:"PS_HOLD (SoC dropped PS_HOLD)",0x85:"SW_RESET",0x86:"RESIN_N_DEBOUNCE",0x87:"KPDPWR_N_DEBOUNCE",0x21E3:"PMIC_SID2_BCL_ALARM",0x31F5:"PMIC_SID3_BCL_ALARM",0x11D0:"PMIC_SID1_OCP",0x21D0:"PMIC_SID2_OCP",0x41D0:"PMIC_SID4_OCP",0x51D0:"PMIC_SID5_OCP"}
RT={1:"WARM_RESET",4:"SHUTDOWN",7:"HARD_RESET"}
bits=lambda d,t: "None" if d==0 else ", ".join(t[i] for i in range(8) if d>>i&1)
def sidpid(d1,d0): 
    d=(d1<<8)|d0; return "SID=0x%X PID=0x%02X IRQ=%d"%(d1>>4,(d>>4)&0xFF,d0&7)
print(f"SDAMs={cnt} push_ptr=0x{ptr:02x} push_sdam={sn} entries_max={maxe}")
for i in range(maxe):
    idx=(st+i*4)%tot; e=[fifo[(idx+k)%tot] for k in range(4)]
    s,ev,d1,d0=e; d=(d1<<8)|d0
    if e==[0,0,0,0]: continue
    if ev==1: m="PON Trigger: "+PON.get(d,sidpid(d1,d0))
    elif ev==2: m="OTP copy complete"
    elif ev==3: m="Trim complete"
    elif ev==4: m="XVLO check complete"
    elif ev==5: m="PMICs detected: SID mask 0x%04X"%d
    elif ev==6: m="*** Reset Trigger: "+RST.get(d,sidpid(d1,d0))
    elif ev==7: m="*** Reset Type: "+RT.get(d0,"UNKNOWN(%d)"%d0)
    elif ev==8: m="Warm reset count: %d"%d0
    elif ev==9: m="FAULT_REASON1=%s; FAULT_REASON2=%s"%(bits(d0,F1),bits(d1,F2)) + ("  ***" if d else "")
    elif ev==0xA: m="FAULT_REASON3=%s"%bits(d0,F3) + ("  ***" if d0 else "")
    elif ev==0xB: m="PBS PC at fault: 0x%04X"%d
    elif ev==0xC: m="Fundamental reset: PON_PBL_STATUS=%s; S3_RESET_REASON=%s"%(bits(d1,PBL),bits(d0,S3))
    elif ev==0xD: m="--- Begin PON sequence"
    elif ev==0xE: m="PON successful"
    elif ev==0xF: m="Waiting on PS_HOLD"
    elif 0x10<=ev<=0x1C: m="PMIC SID%d FAULT_REASON1=%s; FAULT_REASON2=%s"%(ev-0xF,bits(d0,F1),bits(d1,F2)) + ("  ***" if d else "")
    elif ev==0x20: m="VREG check: %sVREG_FAULT"%("" if d else "no ")
    else: m="unknown event 0x%02X data 0x%04X"%(ev,d)
    print(f"{i:3d} [{STATE[s] if s<8 else hex(s):10s}] {m}")
PY
