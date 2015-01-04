## constructors =================================================
## S2MktInt -----------------------------------------------------
function S2MktInt(ds2_mkt_int::Dict{Symbol, Any})
  shock_object = :CapMkt
  shock_type = collect(keys(ds2_mkt_int[:shock]))
  shock = ds2_mkt_int[:shock]
  spot_up_abs_min = ds2_mkt_int[:spot_up_abs_min]
  balance = DataFrame()
  scr = zeros(Float64, 2)
  scen_up = false
  return S2MktInt(shock_object, shock_type, shock,
                  spot_up_abs_min, balance, scr, scen_up)
end

function S2MktInt(p::ProjParam,
                  s2_balance::DataFrame,
                  ds2_mkt_int::Dict{Symbol, Any})
  mkt_int = S2MktInt(ds2_mkt_int)
  mkt_int.balance = deepcopy(s2_balance)
  for int_type_symb in mkt_int.shock_type
    append!(mkt_int.balance,
            s2bal(p, mkt_int,
                  (inv, s2_int) ->
                  mktintshock!(inv, s2_int, int_type_symb),
                  int_type_symb))
  end
  scr!(mkt_int)
  return mkt_int
end

## S2MktEq ------------------------------------------------------
function S2MktEq(ds2_mkt_eq::Dict{Symbol, Any})
  shock_object = :InvPort
  shock_type = collect(keys(ds2_mkt_eq[:shock]))
  eq_type = Dict{Symbol, Symbol}()
  balance = DataFrame()
  corr = ds2_mkt_eq[:corr]
  shock = ds2_mkt_eq[:shock]
  scr = zeros(Float64, 2)
  return S2MktEq(shock_object, shock_type, eq_type, shock,
                 balance, corr, scr)
end

function S2MktEq(p::ProjParam,
                 s2_balance::DataFrame,
                 ds2_mkt_eq::Dict{Symbol, Any},
                 eq2type)
  mkt_eq = S2MktEq(ds2_mkt_eq)
  merge!(mkt_eq.eq2type, eq2type)
  mkt_eq.balance = deepcopy(s2_balance)
  for shock_symb in mkt_eq.shock_type
    append!(mkt_eq.balance,
            s2bal(p, mkt_eq,
                  (inv, s2_eq) ->
                  mkteqshock!(inv, s2_eq, shock_symb),
                  shock_symb))
  end
  scenscr!(mkt_eq)
  return mkt_eq
end


## S2Mkt --------------------------------------------------------
function S2Mkt(ds2_mkt::Dict{Symbol, Any})
  mds = Array(S2Module, 0)
  corr_up = ds2_mkt[:corr](ds2_mkt[:raw], ds2_mkt[:adj], :up)
  corr_down = ds2_mkt[:corr](ds2_mkt[:raw], ds2_mkt[:adj], :down)
  scr = zeros(Float64, 2)
  return S2Mkt(mds, corr_up, corr_down, scr)
end


function S2Mkt(p::ProjParam,
               s2_balance::DataFrame,
               eq2type::Dict,
               ds2_mkt_all::Dict)
  mkt = S2Mkt(ds2_mkt_all[:mkt])
  push!(mkt.mds, S2MktInt(p, s2_balance, ds2_mkt_all[:mkt_int]))
  push!(mkt.mds, S2MktEq(p, s2_balance, ds2_mkt_all[:mkt_eq], eq2type))
  push!(mkt.mds, S2MktProp(p, s2_balance))
  push!(mkt.mds, S2MktSpread(p, s2_balance))
  push!(mkt.mds, S2MktFx(p, s2_balance))
  push!(mkt.mds, S2MktConc(p, s2_balance))
  scen_up = false
  for i = 1:length(mkt.mds)
    if :scen_up in names(mkt.mds[i])
      scen_up = mkt.mds[i].scen_up
    end
  end
  corr = (scen_up ? mkt.corr_up : mkt.corr_down)
  mkt.scr = aggrscr(mkt.mds, corr)
  return mkt
end


## S2Def1 -------------------------------------------------------
function S2Def1(ds2_def_1)
  tlgd = Array(Float64, 0)
  slgd = Array(Float64, 0)
  u = Array(Float64, 0, 0)
  v = Array(Float64, 0)
  scr_par = Dict{Symbol, Vector{Float64}}()
  for i = 1:nrow(ds2_def_1[:scr_par])
    merge!(scr_par,
           [ds2_def_1[:scr_par][i, :range] =>
            [ds2_def_1[:scr_par][i, :threshold_upper],
             ds2_def_1[:scr_par][i, :multiplier]]])
  end
  scr = zeros(Float64, 2)
  return S2Def1(tlgd, slgd, u, v, scr_par, scr)
end

function S2Def1(p::ProjParam,
                ds2_def_1::Dict{Symbol, Any})
  def = S2Def1(ds2_def_1)
  cqs_vec = filter(x -> ismatch(r"cqs", string(x)),
                   names(ds2_def_1[:prob]))
  prob = [ds2_def_1[:prob][1, cqs] for cqs in cqs_vec]
  def.tlgd = zeros(Float64, length(cqs_vec))
  def.slgd = zeros(Float64, length(cqs_vec))
  def.u = Array(Float64, length(cqs_vec), length(cqs_vec))
  def.v = Array(Float64, length(cqs_vec))

  def.v = 1.5 * prob .* (1 .- prob) ./ (2.5 .- prob)
  for i = 1:size(def.u,1), j = 1:1:size(def.u,2)
    def.u[i,j] =
      (1-prob[i]) * prob[i] * (1-prob[j]) * prob[j] /
      (1.25 * (prob[i] + prob[j]) - prob[i] * prob[j])
  end
  invs = InvPort(p.t_0, p.T, p.cap_mkt, p.invs_par...)
  for i = 1:length(invs.igs[:IGCash].investments)
    j = indexin([invs.igs[:IGCash].investments[i].cqs],
                cqs_vec)[1]
    lgd =
      invs.igs[:IGCash].investments[i].lgd *
      invs.igs[:IGCash].investments[i].mv_0
    def.tlgd[j] += lgd
    def.slgd[j] += lgd * lgd
  end
  scr!(def)
  return def
end

## S2Def --------------------------------------------------------
function S2Def(ds2_def)
  mds = Array(S2Module, 0)
  corr = ds2_def[:corr]
  scr = zeros(Float64, 2)
  return S2Def(mds, corr, scr)
end

function S2Def(p::ProjParam,
               s2_balance::DataFrame,
               ds2_def_all::Dict)
  def = S2Def(ds2_def_all[:def])
  push!(def.mds, S2Def1(p, ds2_def_all[:def_1]))
  push!(def.mds, S2Def2(p, s2_balance))
  def.scr = aggrscr(def.mds, def.corr)
  return def
end

## S2LifeQx -----------------------------------------------------
function S2LifeQx(ds2_life_qx::Dict{Symbol, Any})
  shock_object = :LiabIns
  shock_type = [:qx]
  shock = ds2_life_qx[:shock]
  balance = DataFrame()
  corr = eye(1)
  mp_select = Array(Bool, 0)
  scr = zeros(Float64, 2)
  return S2LifeQx(shock_object, shock_type, shock,
                  balance, corr, mp_select, scr)
end

function S2LifeQx(p::ProjParam,
                  s2_balance::DataFrame,
                  ds2_life_qx::Dict{Symbol, Any})
  life_qx = S2LifeQx(ds2_life_qx)
  life_qx.balance = deepcopy(s2_balance)
  select!(p, life_qx)
  for shock_symb in life_qx.shock_type
    append!(life_qx.balance,
            s2bal(p, life_qx,
                  (l_ins, l_qx) -> lifeqxshock!(l_ins, l_qx),
                  shock_symb))
  end
  scenscr!(life_qx)
  return life_qx
end


## S2LifeSx -----------------------------------------------------
## S2LifePx -----------------------------------------------------
## S2LifeCost ---------------------------------------------------
## S2LifeCat ----------------------------------------------------

## S2Life -------------------------------------------------------
function S2Life(ds2_life::Dict{Symbol, Any})
  mds = Array(S2Module, 0)
  corr = ds2_life[:corr]
  scr = zeros(Float64, 2)
  return S2Life(mds, corr, scr)
end

function S2Life(p::ProjParam,
                s2_balance::DataFrame,
                ds2_life_all::Dict)
  life = S2Life(ds2_life_all[:life])
  push!(life.mds, S2LifeQx(p, s2_balance, ds2_life_all[:life_qx]))
  push!(life.mds, S2LifePx(p, s2_balance))
  push!(life.mds, S2LifeMorb(p, s2_balance))
  push!(life.mds, S2LifeSx(p, s2_balance))
  push!(life.mds, S2LifeCost(p, s2_balance))
  push!(life.mds, S2LifeRevision(p, s2_balance))
  push!(life.mds, S2LifeCat(p, s2_balance))
  life.scr = aggrscr(life.mds, life.corr)
  return life
end

## S2Op ---------------------------------------------------------
S2Op(s2_op::Dict{Symbol, Float64}) =
  S2Op(s2_op[:prem_earned], s2_op[:prem_earned_prev],
       s2_op[:tp], s2_op[:cost_ul], 0.0)

## S2 -----------------------------------------------------------
function   S2()
  mds = Array(S2Module, 0)
  balance = DataFrame()
  corr = zeros(Float64, 5, 5)
  bscr = zeros(Float64, 2)
  adj_tp = 0.0
  adj_dt = 0.0
  op = S2Op(zeros(Float64, 5)...)
  scr = 0.0
  return(S2(mds, balance, corr, bscr, adj_tp, adj_dt, op, scr))
end

function  S2(p::ProjParam,
             eq2type::Dict{Symbol, Symbol},
             ds2_mkt_all::Dict,
             ds2_def_all::Dict,
             ds2_life_all::Dict,
             ds2_op::Dict{Symbol, Float64},
             ds2::Dict{Symbol, Any})
  s2 = S2()
  s2.corr = ds2[:corr]
  s2.balance = s2bal(p)
  merge!(ds2_op,
         [:tp => s2.balance[1, :tpg] + s2.balance[1, :bonus]])
  s2.op = S2Op(ds2_op)

  push!(s2.mds, S2Mkt(p, s2.balance, eq2type, ds2_mkt_all))
  push!(s2.mds, S2Def(p, s2.balance, ds2_def_all))
  push!(s2.mds, S2Life(p, s2.balance, ds2_life_all))
  push!(s2.mds, S2Health(p, s2.balance))
  push!(s2.mds, S2NonLife(p, s2.balance))
  s2.bscr = aggrscr(s2.mds, s2.corr)
  scr!(s2.op, s2.bscr[GROSS])
  scr!(s2)
  return s2
end


## other functions ==============================================
## S2 balance sheet (unshocked)
function s2bal(p::ProjParam)
  invs = InvPort(p.t_0, p.T, p.cap_mkt, p.invs_par...)
  proj = Projection(p.proj_par..., p.cap_mkt, invs,
                    p.l_ins, p.l_other, p.dyn)
  return hcat(proj.val_0, DataFrame(scen = :be))
end

## S2 balance sheet (shocked)
function s2bal(p::ProjParam,
               md::S2Module,
               shock!::Any,
               scen::Symbol)
  cpm = deepcopy(p.cap_mkt)
  l_ins = deepcopy(p.l_ins)
  if shock! == nothing
    invs = InvPort(p.t_0, p.T, cpm, p.invs_par...)
  else
    if md.shock_object == :CapMkt shock!(cpm, md) end
    invs = InvPort(p.t_0, p.T, cpm, p.invs_par...)
    if md.shock_object == :InvPort shock!(invs, md) end
    if md.shock_object == :LiabIns shock!(l_ins, md) end
    if md.shock_object == :InvPort_LiabIns
      shock!(cpm, l_ins, md)
    end
  end
  proj = Projection(p.proj_par..., cpm, invs,
                    l_ins, p.l_other, p.dyn)
  return hcat(proj.val_0, DataFrame(scen = scen))
end

## basic own funds
bof(md::S2Module, scen::Symbol) =
  md.balance[md.balance[:scen] .== scen, :invest][1,1] -
  md.balance[md.balance[:scen] .== scen, :tpg][1,1] -
  md.balance[md.balance[:scen] .== scen, :l_other][1,1] -
  md.balance[md.balance[:scen] .== scen, :bonus][1,1]

## future discretionary benefits
fdb(md::S2Module, scen::Symbol) =
  md.balance[md.balance[:scen] .== scen, :bonus][1,1]

## scenario based scr calculation
function scenscr!(mdl::S2Module)
  net =
    bof(mdl, :be) .-
  Float64[bof(mdl, sm) for sm in mdl.shock_type]
  gross =
    net .- fdb(mdl, :be) +
    Float64[fdb(mdl, sm) for sm in mdl.shock_type]

  mdl.scr[NET] = sqrt(net ⋅ (mdl.corr * net))
  mdl.scr[GROSS] = sqrt(gross ⋅ (mdl.corr * gross))
end

## aggregation of scrs of sub-modules
function aggrscr(mds::Vector{S2Module}, corr::Matrix{Float64})
  net = Float64[mds[i].scr[NET] for i = 1:length(mds)]
  gross = Float64[mds[i].scr[GROSS] for i = 1:length(mds)]
  return [sqrt(net ⋅ (corr * net)), sqrt(gross ⋅ (corr * gross))]
end

## S2MktInt -----------------------------------------------------
function scr!(mkt_int::S2MktInt)
  net =
    bof(mkt_int, :be) .-
  Float64[bof(mkt_int, sm) for sm in mkt_int.shock_type]
  gross =
    net .- fdb(mkt_int, :be) +
    Float64[fdb(mkt_int, sm) for sm in mkt_int.shock_type]

  i_up = findin(mkt_int.shock_type, [:spot_up])[1]
  i_down = findin(mkt_int.shock_type, [:spot_down])[1]

  mkt_int.scen_up = net[i_up] >= net[i_down]
  mkt_int.scr[NET] = maximum([0.0, net])
  mkt_int.scr[GROSS] =
    max(0.0, mkt_int.scen_up ? gross[i_up] : gross[i_down])
end

function mktintshock!(cap_mkt::CapMkt,
                      s2_mkt_int,
                      int_type::Symbol)

  len = min(length(cap_mkt.rfr.x),
            length(s2_mkt_int.shock[:spot_up]),
            length(s2_mkt_int.shock[:spot_down]))
  spot = forw2spot(cap_mkt.rfr.x[1:len])


  if int_type == :spot_down
    forw =
      spot2forw(spot .*
                (1 .+ s2_mkt_int.shock[:spot_down][1:len]))
  else
    forw =
      spot2forw(spot .+
                max(spot .* s2_mkt_int.shock[:spot_up][1:len],
                    s2_mkt_int.spot_up_abs_min))
  end
  cap_mkt.rfr.x = deepcopy(forw)
end

## S2MktEq ------------------------------------------------------
function mkteqshock!(invs::InvPort, mkt_eq, eq_type::Symbol)
  invs.mv_0 -= invs.igs[:IGStock].mv_0
  invs.igs[:IGStock].mv_0 = 0.0
  for invest in invs.igs[:IGStock].investments
    if mkt_eq.eq2type[invest.name] == eq_type
      invest.mv_0 *= (1 - mkt_eq.shock[eq_type])
    end
    invs.igs[:IGStock].mv_0 += invest.mv_0
  end
  invs.mv_0 += invs.igs[:IGStock].mv_0
end

## S2Def1 -------------------------------------------------------
function scr!(def::S2Def1)
  var = def.tlgd ⋅ (def.u * def.tlgd) + def.v ⋅ def.slgd
  sigma_norm = -sqrt(var)/sum(def.tlgd)
  if sigma_norm <= def.scr_par[:low][1]
    def.scr[NET] = def.scr_par[:low][2] * sqrt(var)
  elseif sigma_norm <= def.scr_par[:medium][1]
    def.scr[NET] = def.scr_par[:medium][2] * sqrt(var)
  else
    def.scr[NET] = sum(def.tlgd)
  end
  def.scr[GROSS] = def.scr[NET]
end

## S2LifeQx -----------------------------------------------------
## identify those model points that are subject to mortality
## risk. This function does not properly take into account
## second order effects due to the effect of boni.
## However, for realistic portfolios second order effects are
## unlikely to change the set of identified model points.
function select!(p::ProjParam, life_qx::S2LifeQx)
  life_qx.mp_select = Array(Bool, length(p.l_ins.mps))
  invs = InvPort(p.t_0, p.T, p.cap_mkt, p.invs_par...)
  for (m, mp) in enumerate(p.l_ins.mps)
    tp = tpg(p.t_0,
             p.cap_mkt.rfr.x,
             invs.igs[:IGCash].cost.rel,
             mp)
    mp_shock = deepcopy(mp)
    lifeqxshock!(mp_shock, life_qx)
    tp_shock = tpg(p.t_0,
                   p.cap_mkt.rfr.x,
                   invs.igs[:IGCash].cost.rel,
                   mp_shock)
    life_qx.mp_select[m] = (tp_shock > tp)
  end
end


function lifeqxshock!(mp::ModelPoint,  life_qx::S2LifeQx)
  mp.prob[:qx] =
    min(1, (1 + life_qx.shock) * array(mp.prob[:qx]))
  mp.prob[:sx] = min(1 .- mp.prob[:qx], mp.prob[:sx])
  mp.prob[:px] =  1.0 .- mp.prob[:qx] - mp.prob[:sx]
end

function lifeqxshock!(l_ins::LiabIns, life_qx::S2LifeQx)
  for (m, mp) in enumerate(l_ins.mps)
    if life_qx.mp_select[m]
      lifeqxshock!(mp, life_qx)
    end
  end
end



## S2Op ---------------------------------------------------------
function scr!(op::S2Op, bscr)
  op_prem =
    0.04 *
    (op.prem_earned +
       max(0, 1.2 * (op.prem_earned - op.prem_earned_prev)))
  op_tp = 0.0045 * max(0, op.tp)
  op.scr =
    min(0.3 * bscr, max(op_prem, op_tp)) + 0.25 * op.cost_ul
end

## S2 -----------------------------------------------------------

function scr!(s2::S2)
  s2.adj_dt = 0.0 ## fixme: deferred tax not implemented
  s2.adj_tp =
    max(0.0, min(s2.bscr[GROSS] - s2.bscr[NET], fdb(s2, :be)))
  s2.scr = s2.bscr[GROSS] - s2.adj_tp - s2.adj_dt + s2.op.scr
end


