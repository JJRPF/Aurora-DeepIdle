import re,sys
p='/home/jjrpfister/deepidle/aura/proxyclient/m1n1/hv/__init__.py'
s=open(p).read()
if 'HV_UNMASK' in s: print('already'); sys.exit(0)
open(p+'.bak-before-unmask','w').write(s)
old='''            self.log(f"Skip: msr {name}, x{iss.Rt} = {value:x}")
            if value & 1:
                self.log("Guest is shutting down CPU")
                self.p.hv_exit_cpu()
                del self.started_cpus[self.ctx.cpu_id]
'''
new='''            if os.environ.get("HV_UNMASK"):
                self.log(f"UNMASK: msr {name}, x{iss.Rt} = {value:x} passed to the hardware")
                sys.stdout.flush()
                self.u.msr(enc, value)
            else:
              self.log(f"Skip: msr {name}, x{iss.Rt} = {value:x}")
              if value & 1:
                self.log("Guest is shutting down CPU")
                self.p.hv_exit_cpu()
                del self.started_cpus[self.ctx.cpu_id]
'''
assert old in s; s=s.replace(old,new,1)
old2='''        elif enc in skip or (enc in ro and iss.DIR == MSR_DIR.WRITE):
            if iss.DIR == MSR_DIR.READ:'''
new2='''        elif os.environ.get("HV_UNMASK") and enc == ACC_OVRD_EL1 and iss.DIR == MSR_DIR.WRITE:
            if iss.Rt != 31:
                value = ctx.regs[iss.Rt]
            self.log(f"UNMASK: msr {name}, x{iss.Rt} = {value:x} passed to the hardware")
            sys.stdout.flush()
            self.u.msr(enc, value)
        elif enc in skip or (enc in ro and iss.DIR == MSR_DIR.WRITE):
            if iss.DIR == MSR_DIR.READ:'''
assert old2 in s; s=s.replace(old2,new2,1)
open(p,'w').write(s); print('patched')
