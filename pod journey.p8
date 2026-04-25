pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- pod: dolphin pod wave riding

----------------------------------------
-- constants
----------------------------------------
grav=0.055
drag_x=0.992
drag_y=0.985
thr=0.09
rspd=0.014
rspd_t=0.005
mspd_i=2.5
mspd_max=3.3
jmspd_max=6.0   -- journey mode speed ceiling
wtr=300
ww=512
buoy=0.3
maxdep=220
drown_t=300
cam_spd=0.24

gmode=0   -- 0=menu, 2=playing
px2=false  -- x2 sprite scale toggle

----------------------------------------
-- init
----------------------------------------
function _init()
 cartdata("surf_hiscore")
 hscr=dget(0)
 hscr_e=dget(1)
 gmode=0
 menu_t=0
end

function start_game()
 gmode=2
 p={
  x=256,y=315,
  vx=0,vy=0,
  a=0,
  alive=true,
  uwt=0,
  max_dep=0,
  fall_spd=0,
  flipped=false,
 }
 prt={}
 pop={}
 brd={}
 shrk={}
 scr=0
 scr_e=0
 mspd=mspd_i
 entry_boost=0
 p_outline_c=14
 death_freeze_t=0
 death_sx=0
 death_sy=0
 death_sa=0
 p_spd=0
 wave_off=0
 rot_acc=0
 rot_dir=0
 prev_a=0
 shk=0
 shx=0
 shy=0
 hitstop=0
 cam_x=256
 cam_y=315
 perf_t=0
 perf_wx=0
 perf_wy=0
 pod_gain_t=0
 banner_t=0
 banner_txt=""
 banner_c=7

 -- temp score system
 temp_scr=0
 temp_flash=0
 temp_disp_t=0
 pending_scr=0
 pending_scr_e=0
 pending_t=0
 disp_temp=0
 disp_emult=0
 disp_pm=0
 disp_earned=0
 disp_tier=0
 entry_wx=0
 entry_wy=0

 -- quality points for pod gain
 quality_pts=0

 -- shark hit state
 inv_t=0
 catch_up_t=0
 dying_dphs={}
 loss_prot=0
 air_dist=0   -- journey: horiz distance accumulated in air
 decay_t=0    -- frames before speed decay resumes

 -- position history trail (circular buffer)
 trail={}
 trail_len=60
 for i=1,trail_len do
  add(trail,{x=p.x,y=p.y,a=p.a})
 end
 trail_i=1

 -- pod: 4 followers
 pod={}
 for i=1,4 do
  add(pod,{
   x=p.x-i*12,
   y=p.y,
   a=p.a,
   alive=true,
   chain_pos=i,
   perp_off=0,
   wave_freq=0.4+rnd(0.5),
   wave_amp=3+rnd(4),
   wave_phase=rnd(1),
   dying=false,
   death_timer=0,
   death_vx=0,
   death_vy=0,
  })
 end

 -- parallax cloud layers
 cld={}
 for i=1,17 do
  add(cld,{
   x=rnd(ww),y=rnd(450)-280,
   w=8+rnd(12),h=6+rnd(4),
   cs=flr(rnd(3)),
   sp=0.2+rnd(0.15)
  })
 end
 for i=1,16 do
  add(cld,{
   x=rnd(ww),y=rnd(440)-250,
   w=14+rnd(18),h=8+rnd(6),
   cs=flr(rnd(3)),
   sp=0.45+rnd(0.2)
  })
 end
 for i=1,13 do
  add(cld,{
   x=rnd(ww),y=rnd(460)-230,
   w=22+rnd(30),h=14+rnd(8),
   cs=flr(rnd(3)),
   sp=0.75+rnd(0.2)
  })
 end

 for i=1,5 do add_brd(true) end
 add_shrk()
end

function add_shrk()
 local dir=rnd(1)<0.5 and 1 or -1
 local sy=wtr+48+rnd(40)
 add(shrk,{
  x=(cam_x+dir*110+ww)%ww,
  y=sy,
  vx=dir*(0.3+rnd(0.4)),
  fr=dir>0,
  bob=rnd(1)
 })
end

function add_brd(scatter)
 local dir=rnd(1)<0.5 and 1 or -1
 local r=rnd(1)
 local by
 if r<0.3 then
  by=wtr-12-rnd(18)
 elseif r<0.65 then
  by=wtr-45-rnd(50)
 else
  by=wtr-110-rnd(80)
 end
 local bx
 if scatter then
  bx=rnd(ww)
 else
  bx=(cam_x+dir*100+ww)%ww
 end
 add(brd,{
  x=bx,
  y=by,
  vx=dir*(0.6+rnd(0.7)),
  bob=rnd(1),
 })
end

----------------------------------------
-- score helpers
----------------------------------------
function add_score(e)
 if e<=0 then return end
 -- scale e down to match current exponent
 for i=1,scr_e do e=max(1,flr(e/10)) end
 -- promote if adding e would overflow
 while scr+e>=30000 do
  scr=flr(scr/10)
  e=max(1,flr(e/10))
  scr_e+=1
 end
 scr+=e
end

function score_str(s,se)
 if se>0 then
  return tostr(flr(s)).."e+"..tostr(se)
 end
 return tostr(flr(s))
end

function scr_gt(a,ae,b,be)
 if ae~=be then return ae>be end
 return a>b
end

----------------------------------------
-- world to screen
----------------------------------------
function w2s(wx,wy)
 local dx=(wx-cam_x+ww/2)%ww-ww/2
 return 64+dx+shx,
        64+(wy-cam_y)+shy
end

function on_scr(x,y)
 return x>-2 and x<130 and
        y>-2 and y<130
end

----------------------------------------
-- pod helpers
----------------------------------------
function pod_alive_count()
 local n=0
 for d in all(pod) do
  if d.alive then n+=1 end
 end
 return n
end

function pod_mult()
 return pod_alive_count()+1
end

function kill_pod_member(d)
 d.dying=true
 d.alive=false
 d.death_timer=90
 d.death_vx=cos(d.a)*p_spd*0.5
 d.death_vy=sin(d.a)*p_spd*0.5
end

function max_pod_count()
 return 4
end

-- effective speed: base + per-jump entry boost
function eff_spd()
 return min(jmspd_max,mspd+entry_boost)
end

function kill_pod_multi()
 local to_kill=1
 local killed=0
 for i=#pod,1,-1 do
  if killed>=to_kill then break end
  if pod[i].alive and not pod[i].dying then
   kill_pod_member(pod[i])
   killed+=1
  end
 end
 if killed<to_kill then
  die()
  return false
 end
 return true
end

function gain_pod_member()
 if pod_alive_count()>=max_pod_count() then return end
 local alive=pod_alive_count()
 local cp,po
 if alive<4 then
  cp=alive+1
  po=0
 else
  local extra=alive-4
  cp=extra%4+1
  local ring=flr(extra/4)+1
  local side=(extra%2==0) and 1 or -1
  po=side*(8+ring*3)
 end
 local last=p
 for i=#pod,1,-1 do
  if pod[i].alive then
   last=pod[i]
   break
  end
 end
 add(pod,{
  x=last.x-12,
  y=last.y,
  a=last.a,
  alive=true,
  chain_pos=cp,
  perp_off=po,
  wave_freq=0.4+rnd(0.5),
  wave_amp=3+rnd(4),
  wave_phase=rnd(1),
  dying=false,
  death_timer=0,
  death_vx=0,
  death_vy=0,
 })
 pod_gain_t=30
end

----------------------------------------
-- update 60fps
----------------------------------------
function _update60()
 if gmode==0 then
  menu_t+=1
  if btnp(4) or btnp(5) then start_game() end
  return
 end

 if hitstop>0 then
  hitstop-=1
  if hitstop>2 then
   if hitstop%3~=0 then return end
  else
   return
  end
 end

 if shk>0 then
  shx=rnd(shk*2)-shk
  shy=rnd(shk*2)-shk
  shk*=0.82
  if shk<0.3 then shk=0 end
 else
  shx=0
  shy=0
 end

 if not p.alive then
  upd_prt()
  upd_dying()
  if death_freeze_t>0 then
   death_freeze_t-=1
   if btnp(4) or btnp(5) then death_freeze_t=0 end
  else
   if btnp(4) or btnp(5) then
    gmode=0
   end
  end
  return
 end

 if inv_t>0 then inv_t-=1 end
 if catch_up_t>0 then catch_up_t-=1 end
 if temp_flash>0 then temp_flash-=1 end
 if loss_prot>0 then loss_prot-=1 end
 if pending_t>0 then
  pending_t-=1
  if pending_t==0 and pending_scr>0 then
   add_score(pending_scr) pending_scr=0
  end
 end

 upd_p()
 p_spd=sqrt(p.vx*p.vx+p.vy*p.vy)

 -- record player position in trail buffer
 trail[trail_i]={x=p.x,y=p.y,a=p.a}
 trail_i=trail_i%trail_len+1

 -- camera
 local cdx=(p.x-cam_x+ww/2)%ww-ww/2
 -- hard cap: player can't drift more than 44px right of screen center
 if cdx>44 then
  cam_x=(cam_x+(cdx-44)+ww)%ww
  cdx=44
 end
 local cspd=p.y<=wtr and 0.4 or cam_spd
 cam_x=(cam_x+cdx*cspd)%ww
 cam_y+=(p.y-cam_y)*cspd

 wave_off+=p.vx*1.5

 -- airborne: flip detection + temp score
 if p.y<=wtr then
  local flip_thresh=0.667
  local da=(p.a-prev_a+0.5)%1-0.5
  if abs(da)>0.001 then rot_dir=sgn(da) end
  rot_acc+=da
  if abs(rot_acc)>=flip_thresh then
   local sign=rot_acc>0 and 1 or -1
   rot_acc-=sign*flip_thresh
   local is_back=(p.vx>=0 and rot_dir<0)
                  or (p.vx<0 and rot_dir>0)
   local gain=is_back and 2 or 1
   temp_scr+=gain
   temp_flash=5
   shk=2
   p.flipped=true
   add_popup("+"..gain.." flip",p.x,p.y-14,10,-0.08)
  end
  -- accumulate horizontal distance (either direction)
  air_dist+=abs(p.vx)*0.04
 else
  rot_acc=0
  air_dist=0
 end
 -- passive speed decay (1s grace after last entry boost)
 if decay_t>0 then
  decay_t-=1
 else
  local gp=(mspd-mspd_i)/(4.0-mspd_i)
  mspd=max(mspd_i,mspd-gp*gp*0.0013)
 end

 prev_a=p.a

 upd_brd()
 upd_shrk()
 upd_pod()
 upd_dying()
 upd_pop()
 upd_prt()
end

----------------------------------------
-- player physics
----------------------------------------
function upd_p()
 local in_water=p.y>wtr
 local boost=in_water

 local rs=boost and rspd_t or rspd
 local turn_dir=0
 if btn(0) then turn_dir=1 end
 if btn(1) then turn_dir=-1 end
 if in_water and turn_dir~=0 then
  -- resist turning toward sky: harder the more upward-facing the dolphin is
  local sky_diff=(0.75-p.a+0.5)%1-0.5
  local toward_sky=(sky_diff>0 and turn_dir>0) or (sky_diff<0 and turn_dir<0)
  if toward_sky then
   local up_amt=max(0,-sin(p.a))  -- 0 when horizontal/down, 1 when pointing straight up
   rs=rs*(1-up_amt*0.75)
  end
 end
 if turn_dir>0 then p.a+=rs end
 if turn_dir<0 then p.a-=rs end
 p.a%=1

 -- idle underwater: steer facing toward velocity
 if in_water and turn_dir==0 then
  local spd=sqrt(p.vx*p.vx+p.vy*p.vy)
  if spd>0.2 then
   local vel_a=atan2(p.vx,p.vy)
   local diff=(vel_a-p.a+0.5)%1-0.5
   p.a+=mid(-0.003,diff,0.003)
   p.a%=1
  end
 end

 -- velocity steering: bend velocity toward facing (underwater, active turn)
 if in_water then
  local spd=sqrt(p.vx*p.vx+p.vy*p.vy)
  if spd>0.1 and (btn(0) or btn(1)) then
   local vel_a=atan2(p.vx,p.vy)
   local diff=(p.a-vel_a+0.5)%1-0.5
   local sf=mid(0.5,1.5-spd*0.3,1.5)
   local sr=0.02*sf
   local sa=mid(-sr,diff,sr)
   local nva=vel_a+sa
   p.vx=cos(nva)*spd
   p.vy=sin(nva)*spd
  end
 end

 if boost then
  local es=eff_spd()
  local prog_t=(es-mspd_i)/(mspd_max-mspd_i)
  local cur_thr=thr*(1+prog_t*0.8)
  p.vx+=cos(p.a)*cur_thr
  p.vy+=sin(p.a)*cur_thr
  if rnd(1)<0.7 then
   local dx=cos(p.a)
   local dy=sin(p.a)
   add(prt,{
    x=p.x-dx*4,
    y=p.y-dy*4,
    vx=-dx*rnd(1.5)+rnd(0.4)-0.2,
    vy=-dy*rnd(1.5)+rnd(0.4)-0.2,
    l=5+rnd(5),
    c=rnd(1)<0.5 and 9 or 10
   })
  end
 end

 p.vy+=grav

 local es=eff_spd()
 local prog_d=(es-mspd_i)/(mspd_max-mspd_i)
 local drag_ease=prog_d*0.003
 p.vx*=(drag_x+drag_ease)
 p.vy*=(drag_y+drag_ease)

 -- speed cap
 local prog=(es-mspd_i)/(mspd_max-mspd_i)
 local cap=p.y>wtr and es*(1+prog*0.5) or es*(1.5+prog*3.0)
 local s=sqrt(p.vx^2+p.vy^2)
 if s>cap then
  p.vx*=cap/s
  p.vy*=cap/s
 end

 p.x=(p.x+p.vx)%ww
 p.y+=p.vy

 -- air trail: white particles emitted behind player
 if p.y<=wtr and rnd(1)<0.5 then
  local tdx=-cos(p.a)
  local tdy=-sin(p.a)
  local perpx=tdy
  local perpy=-tdx
  local spread=(rnd(1)-0.5)*1.2
  local tspd=1.5+rnd(1.2)
  local ox=(rnd(1)-0.5)*2
  local oy=(rnd(1)-0.5)*2
  add(prt,{
   x=p.x+tdx*7+ox,
   y=p.y+tdy*7+oy,
   vx=p.vx+tdx*tspd+perpx*spread,
   vy=p.vy+tdy*tspd+perpy*spread,
   l=5+rnd(6),c=7,tail=true
  })
 end

 -- water: submersion + buoyancy
 local was_under=p.uwt>0
 local es=eff_spd()
 local prog=(es-mspd_i)/(mspd_max-mspd_i)
 local cur_maxdep=maxdep*(0.5+prog)
 if p.y>wtr then
  local da=(0.25-p.a+0.5)%1-0.5
  p.a+=(da*0.002)
  p.a%=1

  local depth=p.y-wtr
  if depth>p.max_dep then p.max_dep=depth end

  local dep_norm=depth/cur_maxdep
  p.vy-=buoy*(dep_norm^1.4*1.5+0.15)
  local dep_margin=16
  local dep_lim=wtr+cur_maxdep
  if p.y>dep_lim-dep_margin then
   local push=mid(0,(p.y-(dep_lim-dep_margin))/dep_margin,1)
   p.vy-=push*0.08
   local up_diff=(0.25-p.a+0.5)%1-0.5
   p.a+=(up_diff*push*0.02)
   p.a%=1
  end
  if p.y>dep_lim then p.y=dep_lim end
  p.vx*=0.975
  p.vy*=0.975
  p.uwt+=1
  if rnd(1)<0.3 then
   add(prt,{x=p.x+rnd(6)-3,y=p.y,
    vx=rnd(0.4)-0.2,vy=-rnd(1)-0.3,
    l=10+rnd(8),c=7})
  end

  -- water entry: quality check
  if p.uwt==1 then
   p.fall_spd=max(0,p.vy)
   local spd=sqrt(p.vx^2+p.vy^2)
   local flop=0
   local alignment=0
   local quality=0
   local is_rev=false
   if spd>0.3 then
    local mom_a=atan2(p.vx,p.vy)
    local delta=abs(p.a-mom_a)%1
    if delta>0.5 then delta=1-delta end
    is_rev=delta>0.25
    if delta>0.25 then delta=0.5-delta end
    local axis_align=1-(delta/0.25)
    if is_rev and sin(p.a)<0.05 then
     axis_align=0
    end
    local vel_down=max(0,p.vy/spd)
    local nose_down=max(0,sin(p.a))
    local dive=min(vel_down,nose_down)
    local dive_adj=min(1,dive*1.5)
    alignment=max(axis_align,dive_adj)
    local horiz_f=abs(p.vx)/spd
    flop=1-alignment
    -- nose-down penalty reduced when moving horizontally
    local nose_pen=max(0,sin(p.a))
    flop=min(1,flop+nose_pen*nose_pen*0.18*(1-horiz_f))
    quality=max(0,1-delta/0.12)
    if is_rev then quality=0 end
   end
   local edrag=0.5+alignment*0.5
   p.vx*=edrag
   p.vy*=edrag

   if spd>0.7 then
    -- determine entry tier
    -- -1=flop, 0=normal, 1=nice, 2=great, 3=perfect
    local tier=0
    local horiz_f=spd>0.1 and abs(p.vx)/spd or 0
    local flop_thresh=0.45+horiz_f*0.1
    -- near-vertical: horiz component < 30% of speed (no perfect on dives)
    local near_vert=horiz_f<0.3
    if flop>=flop_thresh and p.fall_spd>0.3 then
     tier=-1
    elseif flop<0.065 and not near_vert then tier=3
    elseif flop<0.18 then tier=2
    elseif flop<0.35 then tier=1
    end

    -- belly flop effects
    if tier==-1 and loss_prot<=0 then
     rot_acc=0
     quality_pts=0
     -- lose 50% of filled gauge
     local flop_loss=(mspd-mspd_i)*0.5
     entry_boost=0
     mspd=max(mspd_i,mspd-flop_loss)
     p_outline_c=8
     local ac=pod_alive_count()
     if ac>0 then
      banner_t=90 banner_txt="belly flop!" banner_c=8
      -- spawn dying dolphin at player's position (drifts with camera)
      add(dying_dphs,{
       x=p.x,y=p.y,a=p.a,
       death_timer=75,
       death_vx=p.vx,
       death_vy=-0.6,
       splashed=true,
      })
      -- remove first alive pod member
      for j=1,#pod do
       if pod[j].alive and not pod[j].dying then
        del(pod,pod[j])
        break
       end
      end
      catch_up_t=20 inv_t=60 loss_prot=300
     else
      banner_t=90 banner_txt="belly flop!" banner_c=8
      die()
      return
     end
    end

    -- scoring: dist * (flips+1) * dolphins; 0 flips=x1, 1 flip=x2, etc.
    local pm=pod_mult()
    local earned=0
    local dist=flr(air_dist)
    local fc=temp_scr+1
    if tier~=-1 then
     earned=dist*fc*pm
     if pending_scr>0 then add_score(pending_scr) end
     pending_scr=earned pending_t=90
    end
    disp_temp=dist
    disp_pm=temp_scr  -- raw flip count (0=no flips)
    disp_emult=pm
    disp_earned=earned
    disp_tier=tier
    entry_wx=p.x
    entry_wy=p.y
    if air_dist>0 then
     temp_disp_t=90
    end
    -- set underwater outline color from entry quality
    if tier==1 then p_outline_c=11
    elseif tier==2 then p_outline_c=9
    elseif tier==3 then p_outline_c=-1  -- -1 = rainbow
    elseif tier==-1 then p_outline_c=8  -- belly flop: red
    else p_outline_c=14
    end

    -- entry_boost is set per-jump (not additive), mspd base grows slowly
    entry_boost=0
    local gauge_f=(mspd-mspd_i)/(4.0-mspd_i)  -- 0 at start, 1 at max base
    if tier==1 then
     entry_boost=0.5
     mspd=min(4.0,mspd+0.05)
     decay_t=60
    elseif tier==2 then
     entry_boost=0.4+gauge_f*0.6  -- 0.4 at low gauge, 1.0 at max
     mspd=min(4.0,mspd+0.1)
     decay_t=60
    elseif tier==3 then
     entry_boost=0.6+gauge_f*1.4  -- 0.6 at low gauge, 2.0 at max
     mspd=min(4.0,mspd+0.2)
     decay_t=60
    else
     mspd=max(mspd_i,mspd-0.03)
    end
    -- quality pts earn pod members
    if not p.flipped then
     quality_pts=0
    elseif tier==3 then
     quality_pts+=2
    elseif tier==2 then
     quality_pts+=1
    else
     quality_pts=0
    end
    if quality_pts>=3 then
     quality_pts=0
     gain_pod_member()
    end

    -- tier display: banner + colored splash
    if tier>=1 then
     local tc,tc2,tc3
     if tier==3 then
      tc=10 tc2=9 tc3=7
      banner_t=60 banner_txt="perfect!" banner_c=10
     elseif tier==2 then
      tc=9 tc2=8 tc3=10
      banner_t=60 banner_txt="great!" banner_c=9
     else
      tc=11 tc2=3 tc3=7
      banner_t=60 banner_txt="nice!" banner_c=11
     end
     -- cone spray behind player entry
     local spd=sqrt(p.vx^2+p.vy^2)
     local ba=atan2(-p.vx,-p.vy) -- opposite of velocity
     local np=20+tier*12
     local cone=0.15+tier*0.03
     for i=1,np do
      local a=ba+(rnd(cone*2)-cone)
      local s=(1+rnd(2+tier))
      local pvx=cos(a)*s
      local pvy=sin(a)*s
      -- clamp: only upward particles
      if pvy>0 then pvy=-pvy end
      local pc
      if tier==3 then
       local rb={7,8,9,10,11,12,14,15}
       pc=rb[flr(rnd(#rb))+1]
      else
       pc=rnd(1)<0.5 and tc or (rnd(1)<0.7 and tc2 or tc3)
      end
      add(prt,{x=p.x+rnd(8)-4,y=wtr-1,
       vx=pvx,vy=pvy,
       l=25+rnd(20),
       c=pc})
     end
    end
   end  -- spd>0.7

   temp_scr=0
   air_dist=0
   p.flipped=false
   if spd>0.7 and p.fall_spd>0.4 then
    local splash=1-alignment
    shk=2+splash*5
    local np=4+flr(splash*8)
    for i=1,np do
     add(prt,{x=p.x+rnd(12)-6,y=wtr,
      vx=(rnd(2)-1)*(1+splash),vy=-rnd(2)-0.5,
      l=10+rnd(8),c=7})
    end
   end
  end

  if p.uwt>=drown_t then
   die()
   return
  end
 else
  -- water exit
  if was_under then
   local spd=sqrt(p.vx^2+p.vy^2)
   local flop=0
   if spd>0.01 then
    local nose_dot=(p.vx/spd)*cos(p.a)+(p.vy/spd)*sin(p.a)
    flop=1-max(0,nose_dot)
   end
   local stream=1-flop
   local fall_f=min(1,p.fall_spd/(eff_spd()*0.6))
   local dep_f=min(1,p.max_dep/cur_maxdep)
   local energy=dep_f*fall_f*stream
   local np=2+flr(energy*7)
   for i=1,np do
    add(prt,{x=p.x+rnd(8)-4,y=wtr,
     vx=rnd(2)-1,vy=-rnd(1.5)-energy*1.5,
     l=6+rnd(8),c=7})
   end
   -- reset temp score on exit
   temp_scr=0
  end
  p.max_dep=0
  p.uwt=0
 end
end

function die()
 if pending_scr>0 then add_score(pending_scr) pending_scr=0 end
 p.alive=false
 death_freeze_t=120
 death_sx=p.x
 death_sy=p.y
 death_sa=p.a
 if scr_gt(scr,scr_e,hscr,hscr_e) then
  hscr=scr
  hscr_e=scr_e
  dset(0,hscr)
  dset(1,hscr_e)
 end
 shk=8
 for i=1,15 do
  add(prt,{x=p.x,y=p.y,
   vx=rnd(4)-2,vy=rnd(4)-2,
   l=12+rnd(10),c=8})
 end
end

----------------------------------------
-- birds
----------------------------------------
function upd_brd()
 for i=#brd,1,-1 do
  local b=brd[i]
  b.x=(b.x+b.vx)%ww
  b.bob+=0.05
  b.y+=sin(b.bob)*0.4
  if p.alive and p.y<wtr then
   local dx=(b.x-p.x+ww/2)%ww-ww/2
   local dy=b.y-p.y
   if abs(dx)<7 and abs(dy)<5 then
    local deflect=0.097
    if rnd(1)<0.5 then deflect=-deflect end
    p.a=(p.a+deflect)%1
    p.vx*=0.9
    p.vy*=0.9
    hitstop=2
    shk=2
    temp_scr+=1
    temp_flash=5
    p.flipped=true
    for k=1,3 do
     add(prt,{x=b.x,y=b.y,
      vx=rnd(2)-1,vy=rnd(2)-1.5,
      l=6+rnd(4),c=10})
    end
    deli(brd,i)
    add_brd()
   end
  end
 end
 while #brd<5 do add_brd() end
end

----------------------------------------
-- sharks: kills front dolphin
----------------------------------------
function upd_shrk()
 for i=#shrk,1,-1 do
  local s=shrk[i]
  s.x=(s.x+s.vx)%ww
  s.bob+=0.03
  s.y+=sin(s.bob)*0.2
  s.fr=s.vx>0
  -- player collision (underwater only)
  if p.alive and p.y>wtr and inv_t<=0 and loss_prot<=0 then
   local dx=(s.x-p.x+ww/2)%ww-ww/2
   local dy=s.y-p.y
   if abs(dx)<10 and abs(dy)<6 then
    -- player dolphin dies, gets yanked down
    add(dying_dphs,{
     x=p.x,y=p.y,a=p.a,
     death_timer=75,
     death_vx=p.vx,
     death_vy=p.vy*0.3+0.2,
     splashed=false,
    })

    -- first alive pod member becomes new player
    local new_p=nil
    for j=1,#pod do
     if pod[j].alive and not pod[j].dying then
      new_p=pod[j]
      break
     end
    end

    if new_p then
     del(pod,new_p)
     -- refill trail so followers target current position
     for k=1,trail_len do
      trail[k]={x=p.x,y=p.y,a=p.a}
     end
     catch_up_t=20
     inv_t=60
     loss_prot=300
    else
     die()
     return
    end

    shk=3
    deli(shrk,i)
    add_shrk()
   end
  end
 end
 local mx=min(2,1+(scr_e>0 and 1 or flr(scr/8000)))
 while #shrk<mx do add_shrk() end
end

----------------------------------------
-- pod update
----------------------------------------
function upd_pod()
 -- soft separation pass (airborne only)
 local alive_list={}
 for d in all(pod) do
  if d.alive and not d.dying then add(alive_list,d) end
 end
 if p.y<=wtr then
  -- include player
  for _,d in pairs(alive_list) do
   local ddx=(p.x-d.x+ww/2)%ww-ww/2
   local ddy=p.y-d.y
   local dist=sqrt(ddx*ddx+ddy*ddy)
   if dist>0 and dist<10 then
    local push=(10-dist)*0.02
    d.x=(d.x-ddx/dist*push)%ww
    d.y-=ddy/dist*push
   end
  end
  -- between pod members
  for j=1,#alive_list do
   for k=j+1,#alive_list do
    local a,b=alive_list[j],alive_list[k]
    local ddx=(a.x-b.x+ww/2)%ww-ww/2
    local ddy=a.y-b.y
    local dist=sqrt(ddx*ddx+ddy*ddy)
    if dist>0 and dist<8 then
     local push=(8-dist)*0.015
     local nx,ny=ddx/dist,ddy/dist
     a.x=(a.x+nx*push)%ww
     a.y+=ny*push
     b.x=(b.x-nx*push)%ww
     b.y-=ny*push
    end
   end
  end
 end

 for i,d in pairs(pod) do
  if d.alive and not d.dying then

   -- follow via position history trail
   -- tighter delay at high effective speed
   local spd_bonus=max(0,(eff_spd()-mspd_i)/(mspd_max-mspd_i))
   local delay=flr((7-spd_bonus*2)*d.chain_pos)
   delay=max(6*d.chain_pos,delay)
   local ti=(trail_i-1-delay+trail_len*10)%trail_len+1
   local target_x=trail[ti].x
   local target_y=trail[ti].y
   local target_a=trail[ti].a
   -- clamp max lag so pod never goes off screen
   local max_lag=14+d.chain_pos*12
   local lag_dx=(p.x-target_x+ww/2)%ww-ww/2
   if lag_dx>max_lag then
    target_x=(p.x-max_lag+ww)%ww
   end

   -- world-space y offset for flanking dolphins
   if d.perp_off~=0 then
    target_y+=d.perp_off
   end

   if d.y>wtr then
    local wave=sin(t()*d.wave_freq+d.wave_phase)*d.wave_amp
    target_y+=wave
   end

   local base_fs=d.perp_off~=0 and 0.14 or 0.18-d.chain_pos*0.01
   local follow_speed=base_fs+spd_bonus*0.06
   follow_speed=max(follow_speed,0.12)
   if catch_up_t>0 then follow_speed*=3 end
   local dx=(target_x-d.x+ww/2)%ww-ww/2
   d.x=(d.x+dx*follow_speed)%ww
   d.y+=(target_y-d.y)*follow_speed

   local angle_diff=(target_a-d.a+0.5)%1-0.5
   d.a+=angle_diff*follow_speed*2

  elseif d.dying then
   d.death_timer-=1
   d.death_vy+=0.04
   d.death_vx*=0.97
   d.x+=d.death_vx
   d.y+=d.death_vy
   d.a+=0.01
   if d.y>wtr and d.death_vy>0 and not d.splashed then
    d.splashed=true
    for k=1,3 do
     add(prt,{x=d.x+rnd(6)-3,y=wtr,
      vx=rnd(1.5)-0.75,vy=-rnd(1)-0.3,
      l=6+rnd(4),c=7})
    end
   end
   if d.death_timer<=0 then
    del(pod,d)
   end
  end
 end
end

----------------------------------------
-- dying player dolphins (from shark)
----------------------------------------
function upd_dying()
 for i=#dying_dphs,1,-1 do
  local d=dying_dphs[i]
  d.death_timer-=1
  d.death_vy+=0.04
  d.death_vx*=0.97
  d.x+=d.death_vx
  d.y+=d.death_vy
  d.a+=0.01
  if d.y>wtr and d.death_vy>0 and not d.splashed then
   d.splashed=true
   for k=1,3 do
    add(prt,{x=d.x+rnd(6)-3,y=wtr,
     vx=rnd(1.5)-0.75,vy=-rnd(1)-0.3,
     l=6+rnd(4),c=7})
   end
  end
  if d.death_timer<=0 then
   deli(dying_dphs,i)
  end
 end
end

----------------------------------------
-- popups
----------------------------------------
function add_popup(txt,wx,wy,col,spd)
 add(pop,{x=wx,y=wy,vy=spd or -0.2,
  txt=txt,l=90,c=col or 10})
end

function upd_pop()
 for i=#pop,1,-1 do
  local pp=pop[i]
  pp.y+=pp.vy
  pp.l-=1
  if pp.l<=0 then deli(pop,i) end
 end
end

----------------------------------------
-- particles
----------------------------------------
function upd_prt()
 for i=#prt,1,-1 do
  local pt=prt[i]
  pt.x+=pt.vx
  pt.y+=pt.vy
  if not pt.tail then pt.vy+=0.015 end
  pt.l-=1
  if pt.l<=0 then deli(prt,i) end
 end
end

----------------------------------------
-- sprite rotation
----------------------------------------
function draw_dolph(sx,sy,a)
 a=a%1
 local fx=cos(a)<0
 local fy=sin(a)>0
 local pa=a%0.5
 if pa>0.25 then pa=0.5-pa end
 local idx=min(flr(pa*20),4)
 local nx={7,7,7,5,4}
 local ny={3,2,0,0,0}
 local npx=nx[idx+1]
 local npy=ny[idx+1]
 if fx then npx=7-npx end
 if fy then npy=7-npy end
 if px2 then
  sspr((idx+1)*8,0,8,8,sx-npx*2,sy-npy*2,16,16,fx,fy)
 else
  spr(idx+1,sx-npx,sy-npy,1,1,fx,fy)
 end
end

function draw_dolph_outline(sx,sy,a,oc)
 -- draw 1px outline in color oc
 for c=1,15 do pal(c,oc) end
 for dx=-1,1 do
  for dy=-1,1 do
   if dx~=0 or dy~=0 then
    draw_dolph(sx+dx,sy+dy,a)
   end
  end
 end
 pal()
 draw_dolph(sx,sy,a)
end

----------------------------------------
-- draw
----------------------------------------
function _draw()
 if gmode==0 then
  cls(12)
  local mt=menu_t
  for i=0,5 do
   local cx=(i*43+mt*(.12+i*.02))%172-22
   local cy=8+i*9%42
   local r=3+i%3
   circfill(cx,cy,r*1.1,6)
   circfill(cx-r,cy+1,r*.8,6)
   circfill(cx+r,cy+1,r*.9,6)
   circfill(cx-1,cy-1,r*1.1,7)
   circfill(cx-r-1,cy,r*.8,7)
   circfill(cx+r-1,cy,r*.9,7)
  end
  for i=0,2 do
   local bx=(i*53+130-mt*(.4+i*.15))%152-12
   local by=14+i*16
   local f=flr(sin(mt*.07+i)*2)
   line(bx-5,by+f,bx,by,4)
   line(bx+5,by+f,bx,by,4)
  end
  -- title "pod" with black outline
  for ox=-1,1 do for oy=-1,1 do
   print("pod",58+ox,38+oy,0)
  end end
  print("pod",58,38,7)
  -- hi-score top-right
  print("hi "..hscr,90,4,6)
  -- title subtitle
  print("journey",46,72,7)
  line(46,79,76,79,10)
  -- wave
  rectfill(0,97,127,127,1)
  for wx=0,127,2 do
   pset(wx,97+flr(sin(t()*.3+wx*.04)*2),7)
  end
  -- description (below water)
  local d1="fly far. flip. dive clean."
  local d2="score = dist x flips x pod"
  print(d1,64-#d1*2,104,7)
  print(d2,64-#d2*2,111,6)
  print("x/o start",41,118,12)
  return
 end

 cls(12)

 local wy=64+(wtr-cam_y)+shy

 -- sky dots
 local dot_y=-250
 for sy=0,min(flr(wy)-1,127) do
  local world_y=cam_y+(sy-64)-shy
  if world_y<dot_y and sy%2==0 then
   local dist=dot_y-world_y
   local freq=max(2,min(8,10-flr(dist/40)))
   for xx=sy%freq,127,freq do
    pset(xx,sy,1)
   end
  end
 end

 -- clouds (stable y, cull by extent)
 for c in all(cld) do
  local dxb=(c.x-cam_x+ww/2)%ww-ww/2
  local r=c.w/4
  local ext=r*2+4
  local sh=c.sp<0.4 and 13 or 6
  local hl=c.sp<0.4 and 6 or 7
  local r1=r*1.1 local r2=r*.8 local r3=r*.9
  local sy=64+(c.y-cam_y)*c.sp+shy
  if sy>-ext and sy<128+ext then
   for off=-1,1 do
    local sx=64+(dxb+off*ww)*c.sp+shx
    if sx>-ext and sx<128+ext then
     circfill(sx,sy,r1,sh)
     circfill(sx-r,sy+1,r2,sh)
     circfill(sx+r,sy+1,r3,sh)
     circfill(sx-1,sy-1,r1,hl)
     circfill(sx-r-1,sy,r2,hl)
     circfill(sx+r-1,sy,r3,hl)
    end
   end
  end
 end

 -- water body
 if wy<128 then
  local wy0=max(0,flr(wy))
  rectfill(0,wy0,127,127,1)
  -- dotted depth layers
  for sy=wy0,127,2 do
   local world_y=cam_y+(sy-64)-shy
   local d=world_y-wtr
   if d<0 then d=0 end
   local col,freq
   if d<40 then
    col=12 freq=4
   elseif d<60 then
    col=0  freq=4
   else
    col=0  freq=2
   end
   for xx=sy%freq,127,freq do
    pset(xx,sy,col)
   end
  end
  -- wave surface
  for wx=0,127,2 do
   local wv=sin(t()*0.3+(wx+wave_off)*0.04)*2
            +sin(t()*0.2+(wx+wave_off)*0.018)*1
   local yy=flr(wy+wv)
   if yy>=0 and yy<128 then
    pset(wx,yy,7)
    pset(wx+1,yy,12)
   end
  end
 end

 -- birds
 for b in all(brd) do
  local sx,sy=w2s(b.x,b.y)
  if sx>-10 and sx<138 and sy>-10 and sy<138 then
   local flap=flr(sin(b.bob*3)*2)
   line(sx-5,sy+flap,sx,sy,4)
   line(sx+5,sy+flap,sx,sy,4)
   pset(sx,sy,5)
  end
 end

 -- sharks
 for s in all(shrk) do
  local sx,sy=w2s(s.x,s.y)
  if sx>-20 and sx<148 then
   if s.fr then
    spr(11,sx-8,sy-4)
    spr(12,sx,sy-4)
   else
    spr(12,sx-8,sy-4,1,1,true)
    spr(11,sx,sy-4,1,1,true)
   end
  end
 end

 -- particles
 for pt in all(prt) do
  local sx,sy=w2s(pt.x,pt.y)
  if on_scr(sx,sy) then
   pset(sx,sy,pt.c)
  end
 end

 -- dying player dolphins (from shark)
 for d in all(dying_dphs) do
  if d.death_timer<30 and d.death_timer%4<2 then
  else
   local sx,sy=w2s(d.x,d.y)
   if on_scr(sx,sy) then
    pal(7,8) pal(6,2) pal(12,2)
    draw_dolph(sx,sy,d.a)
    pal()
   end
  end
 end

 -- pod members
 for d in all(pod) do
  if d.alive then
   local sx,sy=w2s(d.x,d.y)
   if on_scr(sx,sy) then
    draw_dolph(sx,sy,d.a)
   end
  end
  if d.dying then
   if d.death_timer<30 and d.death_timer%4<2 then
   else
    local sx,sy=w2s(d.x,d.y)
    if on_scr(sx,sy) then
     pal(7,8) pal(6,2) pal(12,2)
     draw_dolph(sx,sy,d.a)
     pal()
    end
   end
  end
 end

 -- player
 if p.alive then
  -- blink briefly after shark hit
  if inv_t<=0 or t()*8%2<1 then
   local pdx=(p.x-cam_x+ww/2)%ww-ww/2
   local psx=64+pdx+shx
   local psy=64+(p.y-cam_y)+shy
   local oc
   if p_outline_c==-1 then
    -- perfect: rainbow everywhere
    local rb={7,8,9,10,11,12,14,15}
    oc=rb[flr(t()*12)%#rb+1]
   elseif p.y>wtr then
    -- underwater: quality colour
    oc=p_outline_c
   else
    -- above water: black
    oc=0
   end
   draw_dolph_outline(psx,psy,p.a,oc)
  end
 end


 -- floating popups
 for pp in all(pop) do
  local sx,sy=w2s(pp.x,pp.y)
  if on_scr(sx,sy) then
   local c=pp.c
   if pp.l<18 and pp.l%4<2 then c=0 end
   local tx=sx-#pp.txt*2
   for dx=-1,1 do
    for dy=-1,1 do
     if dx~=0 or dy~=0 then
      print(pp.txt,tx+dx,sy+dy,0)
     end
    end
   end
   print(pp.txt,tx,sy,c)
  end
 end

 -- temp score display (airborne)
 if p.alive and p.y<=wtr and air_dist>0 then
  local pdx=(p.x-cam_x+ww/2)%ww-ww/2
  local sx=64+pdx+shx+6
  local sy=64+(p.y-cam_y)+shy-10
  local dist=flr(air_dist)
  local dstr=tostr(dist)
  local fm=temp_scr+1
  local full=temp_scr>0 and (dstr.."x"..fm) or dstr
  for ddx=-1,1 do for ddy=-1,1 do
   if ddx~=0 or ddy~=0 then print(full,sx+ddx,sy+ddy,0) end
  end end
  print(dstr,sx,sy,7)
  if temp_scr>0 then
   print("x",sx+#dstr*4,sy,7)
   print(fm,sx+#dstr*4+4,sy,10)
  end
 end

 -- entry score display: floats up slowly, then accelerates to HUD
 if temp_disp_t>0 then
  temp_disp_t-=1
  -- tier color: nice=green, great=orange, perfect=rainbow
  local tc
  if disp_tier==1 then tc=11
  elseif disp_tier==2 then tc=9
  elseif disp_tier==3 then
   local cols={7,10,11,12,8,14,15,9}
   tc=cols[flr(t()*12)%#cols+1]
  else tc=7 end
  -- phase 1 (90-45): follow player, drift up slowly
  -- phase 2 (45-0): accelerate from detach point toward HUD
  local px,py=w2s(p.x,p.y-16)
  local drift=(90-temp_disp_t)*0.3
  local fx,fy
  if temp_disp_t>45 then
   fx=px
   fy=py-drift
  else
   local t_val=1-(temp_disp_t/45)
   t_val=t_val*t_val*t_val
   local detach_y=py-(90-45)*0.3
   fx=px+(2-px)*t_val
   fy=detach_y+(2-detach_y)*t_val
  end
  if disp_tier==-1 then
   -- belly flop: handled by banner, skip
  elseif temp_disp_t<8 and temp_disp_t%3<1 then
  elseif temp_disp_t>45 then
   -- formula: [dist]x[flips]x[dolphins]  (flip omitted if no flips)
   local dns=tostr(disp_emult)
   local p1=tostr(disp_temp).."x"
   local fs,p2
   if disp_pm>0 then
    fs=tostr(disp_pm+1) p2="x"
   else
    fs="" p2=""
   end
   local full=p1..fs..p2..dns
   local tw=#full*4
   local tx=fx-tw/2
   -- shadow pass
   for ddx=-1,1 do for ddy=-1,1 do
    if ddx~=0 or ddy~=0 then
     print(full,tx+ddx,fy+ddy,0)
    end
   end end
   -- main pass: [white dist] x [yellow flips] x [pink dolphins]
   local cx=tx
   if #p1>0 then print(p1,cx,fy,7) end
   cx+=#p1*4
   if #fs>0 then print(fs,cx,fy,10) end
   cx+=#fs*4
   if #p2>0 then print(p2,cx,fy,7) end
   cx+=#p2*4
   print(dns,cx,fy,14)
  else
   local txt="+"..disp_earned
   local tx=fx-#txt*2
   for ddx=-1,1 do for ddy=-1,1 do
    if ddx~=0 or ddy~=0 then print(txt,tx+ddx,fy+ddy,0) end
   end end
   print(txt,tx,fy,tc)
  end
 end


 -- pod gain text
 if pod_gain_t>0 then
  pod_gain_t-=1
  local sx,sy=w2s(p.x,p.y)
  print("♥",sx+6,sy-8,14)
 end

 -- hud: score (top left, black outline)
 local ss=score_str(scr,scr_e)
 for ddx=-1,1 do for ddy=-1,1 do
  if ddx~=0 or ddy~=0 then print(ss,2+ddx,2+ddy,0) end
 end end
 print(ss,2,2,7)

 -- hud: pod count (top right) ヌ█⬆️ "Nx♥♥♥" with black outline
 local ac=pod_alive_count()
 local hsp=ac>8 and 5 or 6
 local nm=tostr(pod_mult()).."x"
 local hrx=121  -- rightmost heart x (shifted left 3px)
 local nx_x=hrx-(ac-1)*hsp-#nm*4-1
 local hy=2
 -- outline pass for prefix and each heart
 for ddx=-1,1 do for ddy=-1,1 do
  if ddx~=0 or ddy~=0 then
   print(nm,nx_x+ddx,hy+ddy,0)
   for i=1,ac do
    print("♥",hrx-(i-1)*hsp+ddx,hy+ddy,0)
   end
  end
 end end
 -- main pass
 print(nm,nx_x,hy,14)
 for i=1,ac do
  print("♥",hrx-(i-1)*hsp,hy,14)
 end

 -- hud: quality points progress (3 dots below pod count)
 for i=1,3 do
  local c=(i<=quality_pts) and 11 or 1
  circfill(124-(i-1)*4,13,1,c)
 end

 -- hud: drown bar (bottom right)
 if p.alive and p.uwt>10 then
  local pct=p.uwt/drown_t
  local bw=flr(40*(1-pct))
  local bx=86
  rectfill(bx,121,bx+40,125,0)
  if bw>0 then
   local dc=12
   if pct>0.5 then dc=8 end
   if pct>0.8 then dc=2 end
   rectfill(bx,121,bx+bw,125,dc)
  end
  rect(bx,121,bx+40,125,5)
 end

 -- speed gauge (bottom left): base speed only (not entry boost)
 local spd_pct=(mspd-mspd_i)/(4.0-mspd_i)
 local bw=-flr(-spd_pct*40)
 print("spd",1,115,6)
 rectfill(1,121,41,125,0)
 if bw>0 then rectfill(1,121,1+min(bw,40),125,9) end
 rect(1,121,41,125,5)

 -- banner (top center)
 if banner_t>0 then
  banner_t-=1
  local bt=banner_txt
  local bx=64-#bt*2
  local by=6
  local bc=banner_c
  -- perfect banner: rainbow per letter
  if bt=="perfect!" then
   local cols={7,10,11,12,8,14,15,9}
   for i=1,#bt do
    local ci=flr(t()*12+i)%#cols+1
    local c=cols[ci]
    if banner_t<15 and (banner_t+i)%3==0 then c=1 end
    local cx=bx+(i-1)*4
    for dx=-1,1 do for dy=-1,1 do
     if dx~=0 or dy~=0 then print(sub(bt,i,i),cx+dx,by+dy,0) end
    end end
    print(sub(bt,i,i),cx,by,c)
   end
  else
   if banner_t<15 and banner_t%4<2 then bc=1 end
   for dx=-1,1 do for dy=-1,1 do
    if dx~=0 or dy~=0 then print(bt,bx+dx,by+dy,0) end
   end end
   print(bt,bx,by,bc)
  end
 end

 -- death screen
 if not p.alive then
  if death_freeze_t>0 then
   -- freeze: draw sprite at death position
   local dsx,dsy=w2s(death_sx,death_sy)
   draw_dolph_outline(dsx,dsy,death_sa,8)
  else
   rectfill(16,48,111,82,0)
   rect(16,48,111,82,7)
   print("game over",38,52,7)
   print("score: "..score_str(scr,scr_e),34,60,7)
   print("best: "..score_str(hscr,hscr_e),34,68,10)
   print("x/o menu",41,76,6)
  end
 end
end
__gfx__
00000000000000000000000000000077000000000006600000066000000000000006660000000000000000000000000006600000d000dd000000000000000000
00000000000000000000000000000777000766700076670000677600006666000067766000d11100000000006600000066600000dd000dd00000000000000000
00000000000660000006067700007770007667700076670006777760067777600677776000d111000000000066600000666600009dd00ddd0000000000000000
00000000007777770006770000077700077677000776677067777776677777766777777600d111000000000006666666666666669ddddddddddc000000000000
000000006666670000667000007776000766700007766770677777766777777667777760111111111111111106666666666666669ddddddddddc000000000000
000000000000000000600000077006007777000007766770067777600677776006777760d11111111111111006667777777777709dd00ddd0000000000000000
0000000000000000000000000000000000000000000660000067760000666600006776000d111111111111006660000000066000dd000dd00000000000000000
00000000000000000000000000000000000000000000000000066000000000000000000000d11111111100006600000000660000d000dd000000000000000000
__label__
cccccccccccccccccccccccccccccccccccccccccccccccccccc666666cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
c0000000000000cccccccccccccccccccccccccccccccccccccc666666ccccccccccccccccccccccccccccccccccccccccccccccc000000000c0000000000000
c0777077007770ccccccccccccccccccccccccccccccccccccccc6666cccccccccccccccccccccccccccccccccccccccccccccccc0eee0e0e0c0ee0ee0ee0ee0
c0007007007000ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc000e0e0e0c0eeeee0eeeee0
c0777007007770cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0ee00e00c0eeeee0eeeee0
c0700007000070ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc000e0e0e0c00eee000eee00
c0777077707770ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0eee0e0e0cc00e00c00e00c
c0000000000000ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000000007c7000ccc000cc
cccccccccccccccccccccccccccccccccccccccc7c7c7ccccccccccccccccc7c7c7ccccccccccccccccccccccccccccccccccccccccccccc7ccccc7ccccccccc
cccccccccccc7c7c7c7ccccccccccccccccccc7ccccccc7ccccccccccccc7ccccccc7ccccccccccccccccccc7c7c7c7ccccccccccccccc7ccccccccc7ccccccc
11c111c17c7c11c111c17cc111c111c111c17cc111c111c17cc111c1117c11c111c1117c11c111c111c1117c11c111c17c7c11c111c17cc111c111c1117c11c1
7c7c7c7c111111111111117c11111111117c111111111111117c7c7c7c111111111111117c11111111117c111111111111117c7c7c7c11111111111111117c11
c111c111c111c111c111c1117c11c1117c11c111c111c111c111c111c111c111c111c111c17cc111c17cc111c111c111c111c111c111c111c11111111111117c
111111111111111111111111117c7c7c111111111111111111111111111111111111111111117c7c7c1111111111111111111111111111111111111111111111
11c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c1
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c1
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c1
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c1
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c1
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c1
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c1
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c1
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c1
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c111c1
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
01110111011101110111011101110111011101110111011101110111011101110111011101110111011101110111011101110111011101110111011101110111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11011101110111011101110111011101110111011101110111011101110111011101110111011101110111011101110111011101110111011101110111011101
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
0111011101110111011101110111011101110111011101110111011101110111011eeee101110111011101110111011101110111011101110111011101110111
111111111111111111111111111111111111111111111111111111111111111111ee77e111111111111111111111111111111111111111111111111111111111
11011101110111011101110111011101110111011101110111011101110111011ee777e111011101110111011101110111011101110111011101110111011101
1111111111111111111111111111111111111111111111111111111111111111ee777ee111111111111111111111111111111111111111111111111111111111
011101110111011101110111011101110111011101110111011101110111011ee777ee1101110111011101110111011101110111011101110111011101110111
11111111111111111111111111111111111111111111111111111111111111ee7776e11111111111111111111111111111111111111111111111111111111111
11011101110111011101110111011101110111011101110111011101110111e77ee6e10111011101110111011101110111011101110111011101110111011101
11111111111111111111111111111111111111111111111111111111111111eeeeeee11111111111111111111111111111111111111111111111111111111111
01110111011101110111011101110111011101110111011101110111011101110111011101110111011101110111011101110111011101110111011101110111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11011101110111011101110111011101110111011101110111011101110111011101110111011101110111011101110111011101110111011101110111011101
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
01110111011101110111011101110661011101110111011101110111a11101110111011101110111011101110111011101110111011101110111011101110111
11111111111111111111661111116661111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11011101110111011101666111016666110111011101110111011101110111011101110111011101110111011101110111011101110111011101110111011101
11111111111111111111166666666666666611111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
01010101010101010101066666666666666601010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
11111111111111111111166677777777777111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
01010101010101010101666101010106610101010101010771010101010101010101010101010101010101010101010101010101010101010101010101010101
11111111111111111111661111111166111111111111117771111111111111111111111111111111111111111111111111111111111111111111111111111111
01010101010101010101010101010101010101010101077701010101770101010101010101010101010101010101010101010101010101010101010101010101
11111111111111111111111111111111111111111111777111111117771111111111111111111111111111111111111111111111111111111111111111111111
01010101010101010101010101010101010101010107776101010177710101010101010101010101010101010101010101010101010101010101010101010101
11111111111111111111111111111111111111111177116111111777111111111111111111111111111111111111111111111111111111111111111111111111
01010101010101010101010101010101010101010101010101017776010101010101010101010101010101010101010101010101010101010101010101010101
11111111111111111111111111111111111111111111111111177116111111111111111111111111111111111111111111111111111111111111111111111111
01010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
01010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
01010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
01010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
01010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
01010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
01010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
01010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
01010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
01010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
01010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
01010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
01010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
01010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
01010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
01010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
01010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
11661666166111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
06010606060601010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
16661666161611111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
01060601060601010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
16611611166611111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
01010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
15555555555555555555555555555555555555555511111111111111111111111111111111111111111111555555555555555555555555555555555555555551
059990000000000000000000000000000000000005010101010101010101010101010101010101010101015cccccccccccccccccccc000000000000000000051
159990000000000000000000000000000000000005111111111111111111111111111111111111111111115cccccccccccccccccccc000000000000000000051
059990000000000000000000000000000000000005010101010101010101010101010101010101010101015cccccccccccccccccccc000000000000000000051
15555555555555555555555555555555555555555511111111111111111111111111111111111111111111555555555555555555555555555555555555555551
01010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111

__map__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000001200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
