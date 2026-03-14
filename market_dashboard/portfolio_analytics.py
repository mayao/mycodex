from __future__ import annotations

import re
from hashlib import sha256
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

try:
    from ai_insight_model import generate_ai_overlay, generate_stock_detail_overlay
    from market_context import HISTORY_POINTS, fetch_live_bundle, fetch_macro_bundle, load_local_analysis_cache
    from statement_parser import USD_HKD_RATE, load_real_portfolio
    from statement_sources import get_reference_analysis_sources, get_statement_sources
    from universe import ASSETS, CATEGORIES
except ModuleNotFoundError:
    from market_dashboard.ai_insight_model import generate_ai_overlay, generate_stock_detail_overlay
    from market_dashboard.market_context import HISTORY_POINTS, fetch_live_bundle, fetch_macro_bundle, load_local_analysis_cache
    from market_dashboard.statement_parser import USD_HKD_RATE, load_real_portfolio
    from market_dashboard.statement_sources import get_reference_analysis_sources, get_statement_sources
    from market_dashboard.universe import ASSETS, CATEGORIES


CN_TZ = timezone(timedelta(hours=8))
ASSET_BY_SYMBOL = {asset["symbol"]: asset for asset in ASSETS}
CATEGORY_BY_ID = {category["id"]: category for category in CATEGORIES}
HOLDING_META_OVERRIDES: dict[str, dict[str, Any]] = {
    "06606.HK": {
        "symbol": "06606.HK",
        "quote_code": "6606.hk",
        "market": "HK",
        "currency": "HKD",
        "name": "New Horizon Health",
        "name_zh": "诺辉健康",
        "category": "healthcare_special",
        "fundamental_score": 2,
        "risk_level": "高",
        "style": "speculative",
        "business_note": "偏单品与监管主题的医疗成长资产，波动高于主流平台股。",
        "fundamental_note": "需要更严格关注产品兑现和现金流，不适合无纪律重仓。",
        "watch_items": "核心产品销售、监管、现金流、融资",
    },
    "07709.HK": {
        "category": "ai_compute",
        "business_note": "这是海力士方向的两倍杠杆工具，本质属于半导体主题交易仓。",
        "fundamental_note": "工具属性强于公司基本面，重点不在长期价值，而在持有期限与波动控制。",
        "watch_items": "HBM 价格、海力士景气、持有期限、止损纪律",
    },
}
SYMBOL_META_ALIASES = {
    "45769.HK": "06606.HK",
}
REVERSE_SYMBOL_META_ALIASES = {value: key for key, value in SYMBOL_META_ALIASES.items()}
STYLE_LABELS = {
    "quality": "核心资产",
    "platform": "平台型资产",
    "turnaround": "修复仓",
    "leveraged": "杠杆工具",
    "speculative": "高波动卫星",
    "stablecoin": "支付/稳定币",
    "cyclical": "周期成长",
    "high_growth": "高成长",
    "defensive_growth": "防守成长",
    "crypto_beta": "Crypto Beta",
    "unclassified": "其他",
}
PRICE_SOURCE_LABELS = {
    "network": "在线行情",
    "cache": "最近同步价格",
    "statement": "结单价格",
}
MARKET_DATA_SOURCE_LABELS = {
    "nasdaq": "Nasdaq Historical",
    "tencent": "腾讯港股日 K",
    "yahoo": "Yahoo Finance Chart",
    "cache": "最近同步价格",
    "statement": "结单价格",
}
FUNDAMENTAL_LABELS = {
    1: "工具属性",
    2: "偏弱",
    3: "中性",
    4: "稳健",
    5: "强",
}
STYLE_FAMILY_BY_STYLE = {
    "quality": "quality_core",
    "defensive_growth": "quality_core",
    "platform": "platform_repair",
    "turnaround": "platform_repair",
    "cyclical": "cyclical_growth",
    "high_growth": "cyclical_growth",
    "stablecoin": "cyclical_growth",
    "crypto_beta": "event_beta",
    "speculative": "event_beta",
    "leveraged": "tactical_tools",
    "unclassified": "other",
}
STYLE_FAMILY_LABELS = {
    "quality_core": "质量复利",
    "platform_repair": "平台/修复",
    "cyclical_growth": "周期成长",
    "event_beta": "事件高波动",
    "tactical_tools": "杠杆交易",
    "other": "其他",
}
ACTION_PLAYBOOK: dict[str, dict[str, str]] = {
    "00700.HK": {
        "role": "核心底仓",
        "stance": "持有但控上限",
        "risk": "它是好资产，但不是用来对冲其他大亏仓位的万能保险。",
        "action": "保留为港股底仓，但单一资产权重不宜长期维持在 20% 附近以上。",
    },
    "03690.HK": {
        "role": "问题仓",
        "stance": "反弹减仓",
        "risk": "大仓位叠加深度浮亏，正在主导组合波动和情绪。",
        "action": "把目标改成降权而不是回本；优先利用反弹或波段窗口把风险权重降下来。",
    },
    "09988.HK": {
        "role": "修复仓",
        "stance": "保留修复弹性",
        "risk": "估值修复需要业务兑现，不宜被动抬到核心仓级别。",
        "action": "维持修复仓定位，和腾讯分开看待；若云与回购兑现，可保留中等权重。",
    },
    "MSTR": {
        "role": "高 Beta 卫星",
        "stance": "反弹降杠杆",
        "risk": "既有正股，又有卖 Put，等于把 Crypto 波动和杠杆叠在一起。",
        "action": "把它当卫星仓，不再让其兼任方向仓和衍生品收租仓；优先压缩总暴露。",
    },
    "BMNR": {
        "role": "投机仓",
        "stance": "缩到极小仓",
        "risk": "小市值加密题材弹性大，但流动性和估值回撤更快。",
        "action": "不建议继续承接主要风险预算，除非你明确只保留非常小的事件仓位。",
    },
    "NVDA": {
        "role": "核心成长",
        "stance": "核心观察持有",
        "risk": "高位时波动会放大，但它依然是 AI 主线里确定性最高的资产之一。",
        "action": "适合作为美股核心成长仓，重点看仓位纪律，而不是频繁做 T。",
    },
    "AMD": {
        "role": "次核心成长",
        "stance": "观察持有",
        "risk": "AI 兑现度不如 NVDA，容易在景气与估值切换里波动放大。",
        "action": "保留观察仓，等兑现度进一步明确后再决定是否提升权重。",
    },
    "ORCL": {
        "role": "AI 基建仓",
        "stance": "小仓等待修复",
        "risk": "当前成本较高，若继续弱于预期，会拖累组合效率。",
        "action": "先把它当等待验证的 AI 基建仓，不急于补仓摊薄。",
    },
    "CRCL": {
        "role": "主题成长仓",
        "stance": "保留弹性但控仓",
        "risk": "好处是叙事顺，坏处是同样受风险偏好驱动明显。",
        "action": "保留但不宜过度加码，避免和 MSTR/BMNR 一起堆出单边加密贝塔。",
    },
    "META": {
        "role": "现金流成长仓",
        "stance": "继续持有",
        "risk": "权重不大，但如果只是小仓试错，别指望它单独对冲其他亏损。",
        "action": "这类资产更适合稳态复利，可以作为组合质量锚的一部分。",
    },
    "HIMS": {
        "role": "主题仓",
        "stance": "缩仓观察",
        "risk": "医疗成长叠加单品与监管风险，波动不适合做大仓。",
        "action": "更适合事件驱动或轻仓跟踪，不建议再和结构性产品一起叠加暴露。",
    },
    "HOOD": {
        "role": "平台成长仓",
        "stance": "持有观察",
        "risk": "交易活跃度与风险偏好波动会传导到业绩。",
        "action": "保持中等以下权重，和 IBKR 分成成长弹性与稳健券商两类仓看待。",
    },
    "IBKR": {
        "role": "稳健券商仓",
        "stance": "可保留",
        "risk": "弹性不高，但胜在经营质量和波动收敛。",
        "action": "如果想提高组合质量，可以把这类仓位当作券商板块里的稳定器。",
    },
    "07709.HK": {
        "role": "杠杆工具",
        "stance": "只做交易仓",
        "risk": "两倍杠杆产品持有时间越长，路径损耗越明显。",
        "action": "限定持有周期和止损规则，不纳入中长期收益预期。",
    },
    "TSLL": {
        "role": "杠杆工具",
        "stance": "只做交易仓",
        "risk": "这是波动放大器，不是企业基本面仓。",
        "action": "若继续保留，必须把它和长期仓完全分账管理。",
    },
    "XPEV": {
        "role": "高波动成长",
        "stance": "观察或缩仓",
        "risk": "行业竞争和盈利兑现都不稳定，赔率不够时不要恋战。",
        "action": "除非你有很强的行业观点，否则更适合作为轻仓交易仓。",
    },
    "NIO": {
        "role": "弱修复仓",
        "stance": "优先清理尾部",
        "risk": "在高亏损状态下继续占用资金，会拖慢组合重建速度。",
        "action": "把它当需要处理的不良资产，而不是等待奇迹的仓位。",
    },
    "06606.HK": {
        "role": "高风险主题仓",
        "stance": "极小仓跟踪",
        "risk": "流动性、监管和商业兑现都偏弱，承受不了大仓位。",
        "action": "如果继续保留，只适合极小仓位观察，不宜占用过多注意力。",
    },
}
CATEGORY_FUNDAMENTAL_TEMPLATES: dict[str, dict[str, str]] = {
    "hk_internet": {
        "earnings_driver": "核心看广告、交易/佣金、平台抽成、回购与政策环境是否同步改善。",
        "valuation_anchor": "估值更依赖盈利修复和南向风险偏好，而不是单一事件催化。",
        "catalyst": "内需修复、监管常态化、回购与核心业务利润率改善。",
        "balance_sheet": "平台资产现金流通常好于制造业，但政策与竞争会压制估值弹性。",
        "red_flags": "竞争补贴、监管扰动、消费恢复不及预期。",
    },
    "ai_compute": {
        "earnings_driver": "收入核心来自数据中心、云订单、AI 资本开支与算力供需结构。",
        "valuation_anchor": "估值围绕订单能见度、毛利率、供给瓶颈和资本开支兑现程度。",
        "catalyst": "大客户 Capex 指引、产品放量、HBM/云订单与企业客户扩张。",
        "balance_sheet": "前排龙头现金流扎实，后排高弹性标的更依赖景气和融资窗口。",
        "red_flags": "出口限制、估值过热、需求递延或供应链卡点。",
    },
    "crypto_beta": {
        "earnings_driver": "主要由 BTC 价格、链上活跃度、交易量与监管清晰度驱动。",
        "valuation_anchor": "看风险偏好、融资能力、稳定币/交易量增长和合规边界。",
        "catalyst": "BTC 强趋势、稳定币立法、ETF 资金流与交易活跃度提升。",
        "balance_sheet": "波动高于传统成长股，仓位纪律比静态估值更重要。",
        "red_flags": "监管收紧、BTC 回撤、融资成本上升、同一因子重复暴露。",
    },
    "growth_platform": {
        "earnings_driver": "核心由广告、流量、券商交易活跃度和付费服务渗透率决定。",
        "valuation_anchor": "估值依赖利润率提升、用户活跃度和 AI/产品创新带来的再加速。",
        "catalyst": "广告恢复、产品迭代、交易活跃度上升、AI 商业化兑现。",
        "balance_sheet": "成熟平台股现金流和经营杠杆较强，适合承担部分质量仓。",
        "red_flags": "活跃度回落、监管合规压力、风险偏好快速降温。",
    },
    "ev_beta": {
        "earnings_driver": "销量、ASP、价格战、海外扩张与融资环境共同决定弹性。",
        "valuation_anchor": "看交付、亏损收敛和行业竞争格局，赔率常高于确定性。",
        "catalyst": "新车型放量、价格战缓和、政策刺激、海外销售突破。",
        "balance_sheet": "多数仍在投入期，仓位应服从资金消耗与市场风格。",
        "red_flags": "价格战、盈利兑现延后、融资压力、行业需求转弱。",
    },
    "healthcare_special": {
        "earnings_driver": "产品销售、渠道放量、监管节点和现金消耗速度是核心变量。",
        "valuation_anchor": "更像事件驱动或单品兑现交易，适合跟踪验证而非盲目重仓。",
        "catalyst": "产品销售、医保/监管节点、渠道拓展、亏损收窄。",
        "balance_sheet": "若现金流弱或产品单一，基本面容错率会明显下降。",
        "red_flags": "监管变化、单品依赖、销售不及预期、再融资压力。",
    },
    "other": {
        "earnings_driver": "优先追踪主营收入来源、利润率趋势和现金流稳定性。",
        "valuation_anchor": "看盈利兑现、资产负债表质量和市场风险偏好是否匹配。",
        "catalyst": "业绩超预期、回购、政策变化或新业务放量。",
        "balance_sheet": "如果缺少稳定现金流，就不应承担过高的组合权重。",
        "red_flags": "盈利下修、现金流转弱、过度依赖单一叙事。",
    },
}
STYLE_EXECUTION_TEMPLATES: dict[str, str] = {
    "quality": "更适合承担底仓或核心观察仓，而不是高频交易仓。",
    "defensive_growth": "适合作为波动缓冲资产，优先看经营质量而不是极端弹性。",
    "platform": "适合放在修复或成长框架里，关键是盈利兑现而非简单摊平。",
    "turnaround": "必须盯盈利和政策拐点，不成立时要及时降权。",
    "cyclical": "更依赖景气周期和库存变化，仓位应随景气强弱动态调整。",
    "high_growth": "赔率高但估值敏感，适合以节奏管理替代一把梭。",
    "stablecoin": "兼具成长和监管变量，适合在主题顺风时保留弹性。",
    "crypto_beta": "只能拿明确的风险预算，不能和衍生品仓位混账。",
    "speculative": "只适合轻仓或事件仓，不能承担组合修复任务。",
    "leveraged": "本质是交易工具，需单独管理持有周期和退出纪律。",
    "unclassified": "先小仓验证，再决定是否升级为正式配置。",
}
FUNDAMENTAL_DETAIL_OVERRIDES: dict[str, dict[str, str]] = {
    "00700.HK": {
        "business_model": "社交、游戏、广告、支付和云生态共同驱动，是港股里少数兼具流量与现金流的平台资产。",
        "earnings_driver": "视频号广告、游戏新品周期、回购强度与支付/金融科技利润率是关键变量。",
        "valuation_anchor": "估值核心不在高增长想象，而在稳健现金流、回购和政策扰动后的再定价。",
        "catalyst": "视频号商业化提速、游戏版号与新游贡献、持续大额回购。",
        "balance_sheet": "自由现金流和净现金能力强，具备底仓属性。",
        "red_flags": "监管、广告景气回落、游戏节奏不及预期。",
    },
    "03690.HK": {
        "business_model": "本地生活平台龙头，外卖、到店与新业务共同决定利润结构。",
        "earnings_driver": "外卖竞争强度、到店利润率、履约效率和新业务亏损收敛是主线。",
        "valuation_anchor": "估值修复需要利润率兑现，而不是单看收入增长。",
        "catalyst": "补贴趋稳、到店利润恢复、外卖竞争缓和、回购或指引改善。",
        "balance_sheet": "经营体量大，但竞争投入会压制利润释放节奏。",
        "red_flags": "价格战、监管、消费走弱、长期亏损仓位带来的执行失真。",
    },
    "MSTR": {
        "business_model": "本质是以 BTC 储备和资本市场融资能力驱动的高弹性资产负债表工具。",
        "earnings_driver": "BTC 趋势、增发/可转债融资条件和持币规模变化决定弹性。",
        "valuation_anchor": "更像 BTC 杠杆映射，不适合套用传统软件股估值。",
        "catalyst": "BTC 创新高、融资窗口改善、机构资金继续拥挤入场。",
        "balance_sheet": "杠杆与波动都高，和卖 Put 同时存在时风险会成倍放大。",
        "red_flags": "BTC 回撤、融资收紧、溢价压缩。",
    },
    "NVDA": {
        "business_model": "AI 训练与推理平台的核心基础设施，定价权和生态位置都在产业链最前排。",
        "earnings_driver": "数据中心收入、Blackwell 节奏、毛利率和云巨头 Capex 指引。",
        "valuation_anchor": "估值取决于订单能见度是否持续高于市场预期，而不是短期交易情绪。",
        "catalyst": "新架构放量、超大客户追加 Capex、推理需求继续扩散。",
        "balance_sheet": "经营质量极强，但高估值意味着回撤也会更陡。",
        "red_flags": "出口限制、供给约束、AI 需求递延、估值消化不足。",
    },
    "CRCL": {
        "business_model": "围绕 USDC、支付结算与链上美元流通的合规基础设施平台。",
        "earnings_driver": "USDC 流通量、利率环境、支付合作与监管进展。",
        "valuation_anchor": "核心看稳定币渗透率、利息收入质量和合规壁垒。",
        "catalyst": "稳定币法案推进、USDC 增长、支付网络合作扩张。",
        "balance_sheet": "成长性高，但仍属于主题交易密集区，容易受风险偏好影响。",
        "red_flags": "监管边界变化、利率下行过快、竞争平台分流。",
    },
    "META": {
        "business_model": "广告现金流平台叠加 AI 分发和效率提升，是质量型成长资产。",
        "earnings_driver": "广告单价与展示量、AI 提升广告效率、资本开支回报。",
        "valuation_anchor": "看广告利润率、回购、AI 商业化兑现，而不是短期流量噪声。",
        "catalyst": "广告周期改善、Reels/AI 变现、回购与利润率继续抬升。",
        "balance_sheet": "现金流极强，适合承担质量锚角色。",
        "red_flags": "监管罚款、广告周期回落、Capex 过快扩张。",
    },
    "AMD": {
        "business_model": "CPU、GPU、服务器与 AI 加速卡并进，属于 AI 第二梯队里的高质量进攻仓。",
        "earnings_driver": "MI 系列放量、服务器市占率、毛利率和 PC 周期修复。",
        "valuation_anchor": "估值取决于 AI 份额兑现速度和服务器业务增长质量。",
        "catalyst": "MI 系列客户扩张、EPYC 市占率提升、业绩指引上修。",
        "balance_sheet": "经营质量稳健，但兑现速度若不及预期，估值弹性会回吐。",
        "red_flags": "AI 市占率不及预期、竞争加剧、估值先行透支。",
    },
    "09988.HK": {
        "business_model": "电商、云和本地化平台资产组合，核心是效率改善和资本回报重估。",
        "earnings_driver": "电商利润率、云恢复、回购节奏和组织效率提升。",
        "valuation_anchor": "估值修复依赖盈利和回购兑现，不能只靠情绪修复。",
        "catalyst": "云业务改善、回购加强、消费企稳、组织调整见效。",
        "balance_sheet": "现金流和现金储备充足，问题更多在增长质量和市场信心。",
        "red_flags": "电商竞争、云恢复不及预期、政策与消费疲软。",
    },
    "ORCL": {
        "business_model": "数据库与企业云基础设施结合，AI 订单让传统软件平台重获成长溢价。",
        "earnings_driver": "云订单、数据库续费、企业客户扩张与资本开支回报。",
        "valuation_anchor": "看剩余履约义务、云增速和 AI 基建订单兑现。",
        "catalyst": "大型云订单落地、AI 数据中心合作、指引上修。",
        "balance_sheet": "现金流稳定，波动低于纯 AI 高弹性标的。",
        "red_flags": "云执行不达预期、Capex 回报偏弱、企业支出收缩。",
    },
    "07709.HK": {
        "business_model": "这是两倍做多海力士的杠杆工具，不是常规经营型公司。",
        "earnings_driver": "收益完全取决于海力士股价路径、波动和持有期限。",
        "valuation_anchor": "没有传统基本面锚，重点是路径损耗和交易纪律。",
        "catalyst": "HBM 景气、海力士强趋势、短线风险偏好提升。",
        "balance_sheet": "工具属性强，长持会损耗，不适合放进长期收益预期。",
        "red_flags": "趋势反转、持有周期过长、把交易仓误当价值仓。",
    },
}
REFERENCE_FRAMEWORK = [
    "先做组合诊断，再看个股：集中度、融资、衍生品是上层约束，选股逻辑是下层执行。",
    "同时保留五种视角：自上而下宏观、自下而上基本面、趋势动量、估值修复、事件驱动。",
    "把建议写成四段式：核心逻辑、验证指标、失效条件、执行动作，避免只有方向没有处置。",
    "负 Gamma 工具不能当主建仓手段。卖 Put、FCN、杠杆 ETF 只能放在受限额度里。",
    "核心-卫星结构比单纯选股更重要：核心仓追求复利，卫星仓追求赔率，二者不能混账。",
    "关键因子必须被显式高亮：宏观政策、监管、价格位置、基本面质量和仓位纪律缺一不可。",
]


def _normalized_symbol_alias(value: str | None) -> str:
    return re.sub(r"\s+", "", str(value or "").strip().upper())


def _build_symbol_lookup_aliases() -> dict[str, str]:
    aliases: dict[str, str] = {}

    def register(alias: str | None, symbol: str) -> None:
        normalized_alias = _normalized_symbol_alias(alias)
        if normalized_alias:
            aliases.setdefault(normalized_alias, symbol)

    known_symbols = set(ASSET_BY_SYMBOL) | set(HOLDING_META_OVERRIDES)
    for symbol in sorted(known_symbols):
        asset = ASSET_BY_SYMBOL.get(symbol, {})
        canonical_symbol = SYMBOL_META_ALIASES.get(symbol, symbol)
        register(symbol, canonical_symbol)
        register(canonical_symbol, canonical_symbol)
        register(REVERSE_SYMBOL_META_ALIASES.get(symbol), canonical_symbol)
        register(asset.get("quote_code"), canonical_symbol)
        if canonical_symbol.endswith(".HK"):
            digits = canonical_symbol.split(".", 1)[0]
            register(digits, canonical_symbol)
            register(digits.lstrip("0") or "0", canonical_symbol)

    for alias, canonical_symbol in SYMBOL_META_ALIASES.items():
        register(alias, canonical_symbol)
        register(canonical_symbol, canonical_symbol)

    return aliases


SYMBOL_LOOKUP_ALIASES = _build_symbol_lookup_aliases()


def canonicalize_symbol(symbol: str) -> str:
    normalized = _normalized_symbol_alias(symbol)
    if not normalized:
        return ""

    hk_match = re.fullmatch(r"0*(\d{1,5})\.HK", normalized)
    if hk_match:
        normalized = f"{hk_match.group(1).zfill(5)}.HK"
    elif re.fullmatch(r"\d{1,5}", normalized):
        normalized = f"{normalized.zfill(5)}.HK"

    normalized = SYMBOL_META_ALIASES.get(normalized, normalized)
    return SYMBOL_LOOKUP_ALIASES.get(normalized, normalized)


def symbol_variants(symbol: str) -> list[str]:
    variants: list[str] = []
    raw = str(symbol or "").strip()

    def register(candidate: str | None) -> None:
        if candidate and candidate not in variants:
            variants.append(candidate)

    canonical = canonicalize_symbol(raw)
    normalized_raw = _normalized_symbol_alias(raw)

    register(raw)
    register(normalized_raw)
    register(canonical)
    register(SYMBOL_META_ALIASES.get(normalized_raw))
    register(REVERSE_SYMBOL_META_ALIASES.get(normalized_raw))
    register(REVERSE_SYMBOL_META_ALIASES.get(canonical))
    register(SYMBOL_LOOKUP_ALIASES.get(normalized_raw))

    if canonical.endswith(".HK"):
        digits = canonical.split(".", 1)[0]
        register(digits)
        register(digits.lstrip("0") or "0")

    return variants


def lookup_symbol_value(mapping: dict[str, Any], symbol: str, default: Any = None) -> Any:
    for candidate in symbol_variants(symbol):
        if candidate in mapping:
            return mapping[candidate]
    return default


def symbol_matches(left: str | None, right: str | None) -> bool:
    left_canonical = canonicalize_symbol(left or "")
    right_canonical = canonicalize_symbol(right or "")
    return bool(left_canonical and right_canonical and left_canonical == right_canonical)


def fundamental_label(score: int | None) -> str:
    if score is None:
        return "未知"
    return FUNDAMENTAL_LABELS.get(int(score), "中性")


def news_signal_label(score: int) -> str:
    if score >= 4:
        return "显著偏多"
    if score >= 2:
        return "偏多"
    if score <= -4:
        return "显著偏空"
    if score <= -2:
        return "偏空"
    return "中性"


def infer_trend_state(
    current_price: float | None,
    ma20: float | None,
    ma60: float | None,
    reasons: list[str] | None = None,
) -> str:
    if current_price is not None and ma20 is not None and ma60 is not None:
        if current_price >= ma20 >= ma60:
            return "强势上行"
        if current_price >= ma20 and current_price < ma60:
            return "修复抬头"
        if current_price < ma20 < ma60:
            return "弱势下行"
        if current_price < ma20 and current_price >= ma60:
            return "高位震荡"
        return "震荡待确认"

    reason_blob = "；".join(reasons or [])
    if "站上 20 日均线" in reason_blob and "站上 60 日均线" in reason_blob:
        return "强势上行"
    if "站上 20 日均线" in reason_blob:
        return "修复抬头"
    if "仍在 20 日均线下方" in reason_blob and "仍在 60 日均线下方" in reason_blob:
        return "弱势下行"
    if "仍在 20 日均线下方" in reason_blob and "站上 60 日均线" in reason_blob:
        return "高位震荡"
    if reason_blob:
        return "震荡待确认"
    return "无数据"


def factor_score_bucket(value: int) -> int:
    return max(-2, min(2, int(value)))


def trend_factor_score(trend_state: str) -> int:
    return {
        "强势上行": 2,
        "修复抬头": 1,
        "震荡待确认": 0,
        "高位震荡": -1,
        "弱势下行": -2,
        "无数据": 0,
    }.get(trend_state, 0)


def risk_factor_score(holding: dict[str, Any]) -> int:
    level_map = {"低": 2, "中": 1, "中高": 0, "高": -1, "很高": -2}
    score = level_map.get(holding.get("risk_level"), 0)
    if holding.get("style") in {"leveraged", "speculative", "crypto_beta"}:
        score -= 1
    if (holding.get("weight_pct") or 0.0) >= 10:
        score -= 1
    if (holding.get("statement_pnl_pct") or 0.0) <= -40:
        score -= 1
    return factor_score_bucket(score)


def composite_signal_score(
    fundamental_score_factor: int,
    trend_score_factor: int,
    news_score_factor: int,
    macro_score_factor: int,
    risk_score_factor: int,
) -> int:
    score = 50
    score += fundamental_score_factor * 12
    score += trend_score_factor * 8
    score += news_score_factor * 6
    score += macro_score_factor * 6
    score += risk_score_factor * 8
    return max(0, min(100, int(round(score))))


def signal_zone(score: int) -> str:
    if score >= 68:
        return "进攻观察"
    if score >= 52:
        return "中性跟踪"
    return "防守处理"


def unique_strings(values: list[str], limit: int | None = None) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for value in values:
        if not value or value in seen:
            continue
        seen.add(value)
        result.append(value)
        if limit is not None and len(result) >= limit:
            break
    return result


def price_source_label(source: str | None) -> str:
    return PRICE_SOURCE_LABELS.get(source or "statement", "结单价格")


def market_data_source_label(source: str | None) -> str:
    return MARKET_DATA_SOURCE_LABELS.get(source or "statement", "结单价格")


def display_price_source_label(price_source: str | None, market_data_source: str | None) -> str:
    if price_source == "network":
        return f"在线行情 · {market_data_source_label(market_data_source)}"
    if price_source == "cache":
        return market_data_source_label("cache")
    return market_data_source_label("statement")


def provider_summary_text(provider_counts: dict[str, int] | None) -> str:
    ordered = []
    for provider in ["nasdaq", "tencent", "yahoo", "cache", "statement"]:
        count = int((provider_counts or {}).get(provider, 0) or 0)
        if count > 0:
            ordered.append(f"{market_data_source_label(provider)} {count} 只")
    for provider, count in sorted((provider_counts or {}).items()):
        if provider in {"nasdaq", "tencent", "yahoo", "cache", "statement"} or int(count or 0) <= 0:
            continue
        ordered.append(f"{market_data_source_label(provider)} {count} 只")
    return " / ".join(ordered)


def now_cn_date() -> str:
    return datetime.now(CN_TZ).date().isoformat()


def hkd_value(amount: float | None, currency: str | None) -> float:
    if amount is None:
        return 0.0
    return amount if currency == "HKD" else amount * USD_HKD_RATE


def safe_pct(numerator: float, denominator: float) -> float | None:
    if denominator == 0:
        return None
    return numerator / denominator * 100.0


def stable_unit(seed: str) -> float:
    digest = sha256(seed.encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big") / float(2**64 - 1)


def share_demo_scale(seed: str, minimum: float = 0.032, maximum: float = 0.078) -> float:
    return minimum + stable_unit(seed) * (maximum - minimum)


def share_demo_hkd(amount: float | None, seed: str, minimum_non_zero: float = 1200.0) -> float | None:
    if amount is None:
        return None
    base = abs(float(amount))
    if base <= 0:
        return 0.0
    scaled = base * share_demo_scale(seed)
    jitter = 0.92 + stable_unit(f"{seed}:hkd") * 0.18
    return round(max(minimum_non_zero, scaled * jitter), 2)


def share_demo_signed_hkd(amount: float | None, seed: str, minimum_non_zero: float = 900.0) -> float | None:
    if amount is None:
        return None
    scaled = share_demo_hkd(abs(float(amount)), seed, minimum_non_zero=minimum_non_zero)
    if scaled is None:
        return None
    return round(-scaled if float(amount) < 0 else scaled, 2)


def share_demo_quantity(quantity: float | None, seed: str) -> float | int | None:
    if quantity is None:
        return None
    base = abs(float(quantity))
    if base <= 0:
        return 0
    scaled = base * share_demo_scale(f"{seed}:qty", minimum=0.036, maximum=0.082)
    if float(quantity).is_integer():
        return max(1, int(round(scaled)))
    return round(max(0.1, scaled), 2)


def share_demo_price(price: float | None, seed: str) -> float | None:
    if price is None:
        return None
    unit = stable_unit(f"{seed}:price")
    return round(max(0.01, float(price) * (0.84 + unit * 0.22)), 2)


def share_demo_pct(value: float | None, seed: str, floor: float = -22.0, ceil: float = 24.0) -> float | None:
    if value is None:
        return None
    unit = stable_unit(f"{seed}:pct")
    adjusted = float(value) * 0.45 + (unit - 0.5) * 9.5
    return round(max(floor, min(ceil, adjusted)), 2)


def asset_meta(symbol: str, fallback_name: str, market: str, currency: str) -> dict[str, Any]:
    canonical = SYMBOL_META_ALIASES.get(symbol, symbol)
    base = {
        "symbol": canonical,
        "quote_code": "",
        "market": market,
        "currency": currency,
        "name": fallback_name,
        "name_zh": fallback_name,
        "category": "other",
        "fundamental_score": 3,
        "risk_level": "中",
        "style": "unclassified",
        "business_note": "暂无预设逻辑，请结合结单和后续研究补充。",
        "fundamental_note": "暂无预设基本面备注。",
        "watch_items": "仓位变化、资金占用、后续催化",
    }
    meta = {**base, **ASSET_BY_SYMBOL.get(canonical, {}), **HOLDING_META_OVERRIDES.get(canonical, {})}
    return meta


def normalize_holding(row: dict[str, Any], total_value_hkd: float) -> dict[str, Any]:
    meta = asset_meta(row["symbol"], row["name"], row["market"], row["currency"])
    statement_value_hkd = hkd_value(row.get("statement_value"), row.get("currency"))
    statement_pnl_hkd = hkd_value(row.get("statement_pnl"), row.get("currency"))
    avg_cost = row.get("avg_cost")
    price = row.get("statement_price")
    pnl_pct = safe_pct(row.get("statement_pnl") or 0.0, row.get("cost_value") or 0.0)
    weight_pct = safe_pct(statement_value_hkd, total_value_hkd) or 0.0
    category = CATEGORY_BY_ID.get(meta["category"], {"name": "其他持仓"})

    return {
        "symbol": meta["symbol"],
        "name": meta.get("name_zh") or row["name"],
        "name_en": meta.get("name") or row["name"],
        "quote_code": meta.get("quote_code"),
        "assetclass": meta.get("assetclass", "stocks"),
        "market": row["market"],
        "currency": row["currency"],
        "quantity": row["quantity"],
        "avg_cost": avg_cost,
        "statement_price": price,
        "statement_value": row.get("statement_value"),
        "statement_value_hkd": round(statement_value_hkd, 2),
        "statement_pnl": row.get("statement_pnl"),
        "statement_pnl_hkd": round(statement_pnl_hkd, 2),
        "statement_pnl_pct": round(pnl_pct, 2) if pnl_pct is not None else None,
        "weight_pct": round(weight_pct, 2),
        "account_count": row["account_count"],
        "accounts": row["accounts"],
        "category": meta["category"],
        "category_name": category["name"],
        "fundamental_score": meta["fundamental_score"],
        "fundamental_label": fundamental_label(meta["fundamental_score"]),
        "risk_level": meta["risk_level"],
        "style": meta["style"],
        "style_label": STYLE_LABELS.get(meta["style"], "其他"),
        "business_note": meta["business_note"],
        "fundamental_note": meta["fundamental_note"],
        "watch_items": meta["watch_items"],
    }


def fundamental_details_for_holding(holding: dict[str, Any]) -> dict[str, str]:
    category_defaults = CATEGORY_FUNDAMENTAL_TEMPLATES.get(
        holding["category"],
        CATEGORY_FUNDAMENTAL_TEMPLATES["other"],
    )
    symbol_override = lookup_symbol_value(FUNDAMENTAL_DETAIL_OVERRIDES, holding["symbol"], {}) or {}
    business_model = symbol_override.get("business_model") or holding["business_note"]
    earnings_driver = symbol_override.get("earnings_driver") or category_defaults["earnings_driver"]
    valuation_anchor = symbol_override.get("valuation_anchor") or category_defaults["valuation_anchor"]
    catalyst = symbol_override.get("catalyst") or category_defaults["catalyst"]
    balance_sheet = symbol_override.get("balance_sheet") or category_defaults["balance_sheet"]
    red_flags = symbol_override.get("red_flags") or category_defaults["red_flags"]
    quality_line = (
        f"基本面 {holding['fundamental_label']} / 风险级别 {holding['risk_level']}。"
        f"{STYLE_EXECUTION_TEMPLATES.get(holding['style'], STYLE_EXECUTION_TEMPLATES['unclassified'])}"
    )
    return {
        "business_model": business_model,
        "earnings_driver": earnings_driver,
        "quality_line": quality_line,
        "valuation_anchor": valuation_anchor,
        "catalyst": catalyst,
        "balance_sheet": balance_sheet,
        "red_flags": red_flags,
    }


def derivative_underlyings(description: str) -> list[str]:
    matches = set()
    text = description.upper()
    for symbol in list(ASSET_BY_SYMBOL) + list(HOLDING_META_OVERRIDES):
        token = symbol.replace(".HK", "").replace(".US", "")
        if token and token in text:
            matches.add(symbol)
    return sorted(matches)


def derivative_notional(item: dict[str, Any]) -> float:
    if item.get("notional") is not None:
        return abs(float(item["notional"]))
    desc = item.get("description", "")
    strike_match = re.search(r"PUT\s+([\d.]+)", desc.upper())
    quantity = abs(float(item.get("quantity") or 0.0))
    if strike_match and quantity:
        return quantity * 100.0 * float(strike_match.group(1))
    return abs(float(item.get("market_value") or 0.0))


def normalize_trade(item: dict[str, Any]) -> dict[str, Any]:
    side = item.get("side") or ""
    clean_side = "卖出" if "卖" in side else "买入"
    meta = asset_meta(item["symbol"], item["name"], "US" if item["currency"] == "USD" else "HK", item["currency"])
    return {
        "date": item["date"],
        "symbol": meta["symbol"],
        "name": meta.get("name_zh") or item["name"],
        "side": clean_side,
        "quantity": item["quantity"],
        "price": item["price"],
        "currency": item["currency"],
        "broker": item["broker"],
        "account_id": item["account_id"],
    }


def normalize_derivative(item: dict[str, Any]) -> dict[str, Any]:
    estimated_notional = derivative_notional(item)
    underlyings = derivative_underlyings(item.get("description", ""))
    return {
        "symbol": item["symbol"],
        "description": item.get("description", ""),
        "currency": item.get("currency", "USD"),
        "quantity": item.get("quantity"),
        "market_value": item.get("market_value"),
        "unrealized_pnl": item.get("unrealized_pnl"),
        "estimated_notional": round(estimated_notional, 2),
        "estimated_notional_hkd": round(hkd_value(estimated_notional, item.get("currency")), 2),
        "underlyings": underlyings,
        "broker": item["broker"],
        "account_id": item["account_id"],
    }


def build_account_cards(accounts: list[dict[str, Any]]) -> list[dict[str, Any]]:
    cards = []
    for account in accounts:
        holdings_value_hkd = round(
            sum(hkd_value(item.get("statement_value"), item.get("currency")) for item in account.get("holdings", [])),
            2,
        )
        financing_hkd = round(
            sum(abs(hkd_value(cash.get("amount"), cash.get("currency"))) for cash in account.get("cash_balances", []) if (cash.get("amount") or 0.0) < 0),
            2,
        )
        nav_hkd = round(hkd_value(account.get("nav"), account.get("base_currency")), 2)
        top_names = []
        sorted_holdings = sorted(
            account.get("holdings", []),
            key=lambda item: hkd_value(item.get("statement_value"), item.get("currency")),
            reverse=True,
        )
        for item in sorted_holdings[:3]:
            top_names.append(item["name"])
        cards.append(
            {
                "account_id": account["account_id"],
                "broker": account["broker"],
                "statement_date": account["statement_date"],
                "base_currency": account["base_currency"],
                "nav_hkd": nav_hkd,
                "holdings_value_hkd": holdings_value_hkd,
                "financing_hkd": financing_hkd,
                "holding_count": len(account.get("holdings", [])),
                "trade_count": len(account.get("recent_trades", [])),
                "derivative_count": len(account.get("derivatives", [])),
                "risk_notes": account.get("risk_notes", []),
                "top_names": "、".join(top_names),
            }
        )
    cards.sort(key=lambda item: item["nav_hkd"], reverse=True)
    return cards


def build_breakdown(rows: list[dict[str, Any]], key: str, label_key: str) -> list[dict[str, Any]]:
    grouped: dict[str, dict[str, Any]] = {}
    total = sum(item["statement_value_hkd"] for item in rows)
    for row in rows:
        group_id = row[key]
        entry = grouped.setdefault(
            group_id,
            {
                "id": group_id,
                "label": row[label_key],
                "value_hkd": 0.0,
                "count": 0,
            },
        )
        entry["value_hkd"] += row["statement_value_hkd"]
        entry["count"] += 1
    result = []
    for item in grouped.values():
        result.append(
            {
                **item,
                "value_hkd": round(item["value_hkd"], 2),
                "weight_pct": round(safe_pct(item["value_hkd"], total) or 0.0, 2),
            }
        )
    result.sort(key=lambda item: item["value_hkd"], reverse=True)
    return result


def build_theme_breakdown(holdings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, dict[str, Any]] = {}
    total = sum(item["statement_value_hkd"] for item in holdings)
    for row in holdings:
        entry = grouped.setdefault(
            row["category"],
            {
                "id": row["category"],
                "label": row["category_name"],
                "value_hkd": 0.0,
                "count": 0,
                "members": [],
            },
        )
        entry["value_hkd"] += row["statement_value_hkd"]
        entry["count"] += 1
        entry["members"].append(row)
    result = []
    for entry in grouped.values():
        members = sorted(entry["members"], key=lambda item: item["statement_value_hkd"], reverse=True)
        result.append(
            {
                "id": entry["id"],
                "label": entry["label"],
                "value_hkd": round(entry["value_hkd"], 2),
                "weight_pct": round(safe_pct(entry["value_hkd"], total) or 0.0, 2),
                "count": entry["count"],
                "core_holdings": [item["name"] for item in members[:3]],
                "core_symbols": [item["symbol"] for item in members[:3]],
            }
        )
    result.sort(key=lambda item: item["value_hkd"], reverse=True)
    return result


def build_broker_breakdown(account_cards: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, dict[str, Any]] = {}
    total_nav = sum(item["nav_hkd"] for item in account_cards)
    for card in account_cards:
        entry = grouped.setdefault(card["broker"], {"label": card["broker"], "value_hkd": 0.0, "count": 0})
        entry["value_hkd"] += card["nav_hkd"]
        entry["count"] += 1
    rows = []
    for item in grouped.values():
        rows.append(
            {
                **item,
                "value_hkd": round(item["value_hkd"], 2),
                "weight_pct": round(safe_pct(item["value_hkd"], total_nav) or 0.0, 2),
            }
        )
    rows.sort(key=lambda item: item["value_hkd"], reverse=True)
    return rows


def enrich_holdings_with_live_and_macro(
    holdings: list[dict[str, Any]],
    live_rows: dict[str, dict[str, Any]],
    macro_scores: dict[str, int],
    research_cache: dict[str, Any],
) -> list[dict[str, Any]]:
    recommendation_rows = research_cache.get("recommendations", {}).get("rows", [])
    recommendation_by_symbol = {row["symbol"]: row for row in recommendation_rows if row.get("symbol")}
    news_by_symbol = research_cache.get("news", {}).get("by_symbol", {})
    news_stats_by_symbol = research_cache.get("news", {}).get("stats_by_symbol", {})
    analysis_date_cn = research_cache.get("analysis_date_cn")
    enriched = []
    for item in holdings:
        live_row = live_rows.get(item["symbol"], {})
        cached_reco = lookup_symbol_value(recommendation_by_symbol, item["symbol"], {}) or {}
        cached_news = lookup_symbol_value(news_by_symbol, item["symbol"], []) or []
        cached_stats = lookup_symbol_value(news_stats_by_symbol, item["symbol"], {}) or {}
        macro_score = macro_scores.get(item["category"], 0)
        macro_signal = "中性"
        if macro_score >= 2:
            macro_signal = "顺风"
        elif macro_score <= -2:
            macro_signal = "逆风"
        current_price = live_row.get("current_price")
        if current_price is None:
            current_price = cached_reco.get("price")
        price_source = "statement"
        if live_row.get("history"):
            price_source = "network"
        elif live_row.get("current_price") is not None:
            price_source = "cache"
        elif cached_reco.get("price") is not None:
            price_source = "cache"
        elif current_price is None:
            current_price = item.get("statement_price")
        market_data_source = live_row.get("market_data_source")
        if market_data_source is None and price_source == "cache":
            market_data_source = "cache"
        if market_data_source is None and price_source == "statement":
            market_data_source = "statement"

        position_label = live_row.get("position_label") or cached_reco.get("position_label") or "无数据"
        trend_state = infer_trend_state(
            current_price,
            live_row.get("ma20"),
            live_row.get("ma60"),
            cached_reco.get("reasons") or [],
        )
        news_score = int(cached_stats.get("total_score") or 0)
        news_score_factor = 2 if news_score >= 4 else 1 if news_score >= 2 else -2 if news_score <= -4 else -1 if news_score <= -2 else 0
        macro_score_factor = 2 if macro_score >= 4 else 1 if macro_score >= 2 else -2 if macro_score <= -4 else -1 if macro_score <= -2 else 0
        fundamental_score_factor = factor_score_bucket(item["fundamental_score"] - 3)
        trend_score_factor = trend_factor_score(trend_state)

        enriched_item = {
            **item,
            "live_available": bool(live_row),
            "current_price": current_price,
            "trade_date": live_row.get("trade_date") or analysis_date_cn,
            "change_pct": live_row.get("change_pct", cached_reco.get("change_pct")),
            "change_pct_5d": live_row.get("change_pct_5d", cached_reco.get("change_pct_5d")),
            "ma20": live_row.get("ma20"),
            "ma60": live_row.get("ma60"),
            "range_position_60d": live_row.get("range_position_60d"),
            "position_label": position_label,
            "trend_state": trend_state,
            "history": live_row.get("history", []),
            "normalized_history": live_row.get("normalized_history", []),
            "macro_score": macro_score,
            "macro_signal": macro_signal,
            "news_score": news_score,
            "news_signal": news_signal_label(news_score),
            "news_headline": cached_news[0]["title"] if cached_news else "",
            "news_count": int(cached_stats.get("count") or len(cached_news)),
            "cached_action": cached_reco.get("action"),
            "cached_summary": cached_reco.get("summary"),
            "cached_reasons": cached_reco.get("reasons") or [],
            "price_source": price_source,
            "market_data_source": market_data_source,
            "market_source_label": display_price_source_label(price_source, market_data_source),
        }
        risk_score_factor = risk_factor_score(enriched_item)
        total_signal = composite_signal_score(
            fundamental_score_factor,
            trend_score_factor,
            news_score_factor,
            macro_score_factor,
            risk_score_factor,
        )
        enriched_item.update(
            {
                "factor_scores": {
                    "fundamental": fundamental_score_factor,
                    "trend": trend_score_factor,
                    "news": news_score_factor,
                    "macro": macro_score_factor,
                    "risk": risk_score_factor,
                },
                "signal_score": total_signal,
                "signal_zone": signal_zone(total_signal),
            }
        )
        enriched.append(enriched_item)
    return enriched


def build_broker_risk_chart(account_cards: list[dict[str, Any]], derivatives: list[dict[str, Any]]) -> list[dict[str, Any]]:
    derivative_by_account: dict[str, float] = defaultdict(float)
    for item in derivatives:
        derivative_by_account[item["account_id"]] += item["estimated_notional_hkd"]
    rows = []
    for card in account_cards:
        rows.append(
            {
                "label": card["broker"],
                "account_id": card["account_id"],
                "nav_hkd": card["nav_hkd"],
                "financing_hkd": card["financing_hkd"],
                "derivative_hkd": round(derivative_by_account.get(card["account_id"], 0.0), 2),
            }
        )
    return rows


def build_scatter_points(holdings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    points = []
    for item in holdings[:14]:
        points.append(
            {
                "symbol": item["symbol"],
                "name": item["name"],
                "market": item["market"],
                "x": item["weight_pct"],
                "y": item["statement_pnl_pct"] if item["statement_pnl_pct"] is not None else 0.0,
                "size": item["statement_value_hkd"],
                "category_name": item["category_name"],
                "macro_signal": item["macro_signal"],
            }
        )
    return points


def build_performance_chart(holdings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows = []
    for item in holdings[:10]:
        rows.append(
            {
                "symbol": item["symbol"],
                "name": item["name"],
                "market": item["market"],
                "points": item.get("normalized_history") or [],
                "available": bool(item.get("normalized_history")),
            }
        )
    return rows


def build_style_mix_chart(holdings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, dict[str, Any]] = {}
    for item in holdings:
        family_id = STYLE_FAMILY_BY_STYLE.get(item["style"], "other")
        entry = grouped.setdefault(
            family_id,
            {
                "id": family_id,
                "label": STYLE_FAMILY_LABELS.get(family_id, "其他"),
                "weight_pct": 0.0,
                "weighted_fundamental": 0.0,
                "weighted_pnl": 0.0,
                "count": 0,
                "members": [],
            },
        )
        entry["weight_pct"] += item["weight_pct"]
        entry["weighted_fundamental"] += item["weight_pct"] * item["fundamental_score"]
        entry["weighted_pnl"] += item["weight_pct"] * (item.get("statement_pnl_pct") or 0.0)
        entry["count"] += 1
        entry["members"].append(item)
    rows = []
    for entry in grouped.values():
        weight = entry["weight_pct"] or 1.0
        top_members = sorted(entry["members"], key=lambda item: item["statement_value_hkd"], reverse=True)[:3]
        rows.append(
            {
                "id": entry["id"],
                "label": entry["label"],
                "weight_pct": round(entry["weight_pct"], 2),
                "avg_fundamental": round(entry["weighted_fundamental"] / weight, 2),
                "avg_pnl_pct": round(entry["weighted_pnl"] / weight, 2),
                "count": entry["count"],
                "core_holdings": [item["name"] for item in top_members],
            }
        )
    rows.sort(key=lambda item: item["weight_pct"], reverse=True)
    return rows


def build_price_regime_chart(holdings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    order = ["强势上行", "修复抬头", "震荡待确认", "高位震荡", "弱势下行", "无数据"]
    grouped = {
        label: {"label": label, "weight_pct": 0.0, "count": 0, "avg_signal": 0.0, "members": []}
        for label in order
    }
    for item in holdings:
        label = item.get("trend_state", "无数据")
        entry = grouped.setdefault(label, {"label": label, "weight_pct": 0.0, "count": 0, "avg_signal": 0.0, "members": []})
        entry["weight_pct"] += item["weight_pct"]
        entry["count"] += 1
        entry["avg_signal"] += item.get("signal_score", 0)
        entry["members"].append(item)
    rows = []
    for label in order:
        entry = grouped[label]
        avg_signal = entry["avg_signal"] / entry["count"] if entry["count"] else 0.0
        top_members = sorted(entry["members"], key=lambda item: item["statement_value_hkd"], reverse=True)[:3]
        rows.append(
            {
                "label": label,
                "weight_pct": round(entry["weight_pct"], 2),
                "count": entry["count"],
                "avg_signal": round(avg_signal, 2),
                "core_holdings": [item["name"] for item in top_members],
            }
        )
    return rows


def build_fundamental_deep_dive(holdings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows = []
    for item in holdings[:8]:
        details = fundamental_details_for_holding(item)
        rows.append(
            {
                "symbol": item["symbol"],
                "name": item["name"],
                "weight_pct": item["weight_pct"],
                "category_name": item["category_name"],
                "style_label": item["style_label"],
                "fundamental_label": item["fundamental_label"],
                "signal_score": item.get("signal_score", 50),
                "stance": diagnose_holding(item)["stance"],
                **details,
            }
        )
    return rows


def build_signal_heatmap(holdings: list[dict[str, Any]]) -> dict[str, Any]:
    columns = [
        {"key": "fundamental", "label": "基本面"},
        {"key": "trend", "label": "趋势"},
        {"key": "news", "label": "新闻"},
        {"key": "macro", "label": "宏观"},
        {"key": "risk", "label": "风控"},
    ]
    rows = []
    for item in holdings[:8]:
        rows.append(
            {
                "symbol": item["symbol"],
                "name": item["name"],
                "weight_pct": item["weight_pct"],
                "score": item.get("signal_score", 50),
                "zone": item.get("signal_zone", "中性跟踪"),
                "cells": [
                    {"label": column["label"], "score": item.get("factor_scores", {}).get(column["key"], 0)}
                    for column in columns
                ],
            }
        )
    return {"columns": columns, "rows": rows}


def build_health_radar(
    holdings: list[dict[str, Any]],
    total_nav_hkd: float,
    total_financing_hkd: float,
    total_derivative_notional_hkd: float,
    top5_ratio: float,
) -> list[dict[str, Any]]:
    total_weight = sum(item["weight_pct"] for item in holdings) or 1.0
    quality_score = sum(item["weight_pct"] * item["fundamental_score"] for item in holdings) / total_weight / 5.0 * 100.0
    positive_trend_weight = sum(item["weight_pct"] for item in holdings if item.get("trend_state") in {"强势上行", "修复抬头"})
    negative_trend_weight = sum(item["weight_pct"] for item in holdings if item.get("trend_state") == "弱势下行")
    trend_score = max(0.0, min(100.0, 50.0 + positive_trend_weight * 1.2 - negative_trend_weight * 0.9))
    macro_alignment = sum(item["weight_pct"] * item.get("factor_scores", {}).get("macro", 0) for item in holdings) / total_weight
    macro_score = max(0.0, min(100.0, 50.0 + macro_alignment * 18.0))
    diversification_score = max(10.0, min(100.0, 100.0 - max(0.0, top5_ratio - 35.0) * 1.9))
    financing_ratio = safe_pct(total_financing_hkd, total_nav_hkd) or 0.0
    derivative_ratio = safe_pct(total_derivative_notional_hkd, total_nav_hkd) or 0.0
    leverage_score = max(0.0, min(100.0, 100.0 - financing_ratio * 2.2 - derivative_ratio * 1.1))
    tactical_weight = sum(item["weight_pct"] for item in holdings if item["style"] in {"leveraged", "speculative", "crypto_beta"})
    drawdown_weight = sum(item["weight_pct"] for item in holdings if (item.get("statement_pnl_pct") or 0.0) <= -30)
    discipline_score = max(0.0, min(100.0, 100.0 - tactical_weight * 1.4 - drawdown_weight * 0.9))
    return [
        {
            "label": "质量",
            "value": round(quality_score, 1),
            "summary": f"强基本面仓位约 {sum(item['weight_pct'] for item in holdings if item['fundamental_score'] >= 4):.2f}%，反映组合的盈利质量底子。",
        },
        {
            "label": "趋势",
            "value": round(trend_score, 1),
            "summary": f"顺势仓约 {positive_trend_weight:.2f}% ，弱势下行仓约 {negative_trend_weight:.2f}%。",
        },
        {
            "label": "宏观",
            "value": round(macro_score, 1),
            "summary": "看组合持仓所处主题与当前政策/国际环境是顺风还是逆风。",
        },
        {
            "label": "分散",
            "value": round(diversification_score, 1),
            "summary": f"前五大仓位占比 {top5_ratio:.2f}% ，占比越高，分散分越低。",
        },
        {
            "label": "杠杆",
            "value": round(leverage_score, 1),
            "summary": f"融资约占净资产 {financing_ratio:.2f}% ，衍生品名义本金约占 {derivative_ratio:.2f}%。",
        },
        {
            "label": "纪律",
            "value": round(discipline_score, 1),
            "summary": f"高波动/杠杆/深亏仓合计约 {tactical_weight + drawdown_weight:.2f}% ，越高越需要纪律约束。",
        },
    ]


def build_macro_flash_topics(macro_bundle: dict[str, Any], holdings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows = []
    for item in macro_bundle.get("topics", []):
        impact_labels = "、".join(CATEGORY_BY_ID.get(category, {"name": category})["name"] for category in item["impact_categories"])
        top_headline = item.get("headline_cn") or (item["headlines"][0]["title"] if item.get("headlines") else "暂无标题")
        top_source = item["headlines"][0].get("source") if item.get("headlines") else None
        top_published_at = item["headlines"][0].get("published_at") if item.get("headlines") else None
        impact_weight_pct = round(
            sum(holding["weight_pct"] for holding in holdings if holding["category"] in item.get("impact_categories", [])),
            2,
        )
        rows.append(
            {
                "id": item.get("id"),
                "name": item["name"],
                "severity": item["severity"],
                "impact_categories": item.get("impact_categories", []),
                "summary": item["summary"],
                "headline": top_headline,
                "impact_labels": impact_labels,
                "score": item["score"],
                "source": top_source,
                "published_at": top_published_at,
                "impact_weight_pct": impact_weight_pct,
            }
        )
    rows.sort(
        key=lambda item: (
            {"高": 0, "中": 1, "低": 2}.get(item["severity"], 3),
            -abs(int(item.get("score") or 0)),
            -(float(item.get("impact_weight_pct") or 0.0)),
        )
    )
    return rows


def build_key_drivers(
    holdings: list[dict[str, Any]],
    risk_flags: list[dict[str, str]],
    macro_topics: list[dict[str, Any]],
) -> list[dict[str, str]]:
    drivers: list[dict[str, str]] = []
    if macro_topics:
        top_macro = max(
            macro_topics,
            key=lambda item: (
                {"高": 3, "中": 2, "低": 1}.get(item["severity"], 0),
                abs(item.get("score", 0)),
                item.get("impact_weight_pct", 0.0),
            ),
        )
        macro_tone = "warn" if top_macro["severity"] == "高" and top_macro.get("score", 0) >= 0 else "down" if top_macro.get("score", 0) < 0 else "up"
        drivers.append(
            {
                "title": top_macro["name"],
                "detail": f"{top_macro['headline']} 关联持仓约 {top_macro.get('impact_weight_pct', 0.0):.2f}%。",
                "tone": macro_tone,
            }
        )
    if risk_flags:
        drivers.append(
            {
                "title": risk_flags[0]["title"],
                "detail": risk_flags[0]["detail"],
                "tone": "down",
            }
        )
    opportunity = next(
        (
            item
            for item in sorted(holdings, key=lambda row: (row.get("signal_score", 0), row["weight_pct"]), reverse=True)
            if item["fundamental_score"] >= 4
        ),
        None,
    )
    if opportunity:
        drivers.append(
            {
                "title": f"{opportunity['name']} 可作为高质量观察窗口",
                "detail": (
                    f"当前信号分数 {opportunity.get('signal_score', 0)}，价格来源 {opportunity.get('price_source', 'statement')}，"
                    f"处于 {opportunity.get('trend_state', '无数据')} / {opportunity.get('position_label', '无数据')}。"
                ),
                "tone": "up",
            }
        )
    weak_spot = next(
        (
            item
            for item in sorted(holdings, key=lambda row: (row["weight_pct"], -(row.get("signal_score", 50))), reverse=True)
            if item["style"] in {"leveraged", "speculative", "crypto_beta"} or item.get("signal_score", 50) < 48
        ),
        None,
    )
    if weak_spot:
        drivers.append(
            {
                "title": f"{weak_spot['name']} 需要更强风控",
                "detail": (
                    f"当前信号分数 {weak_spot.get('signal_score', 0)}，"
                    f"{weak_spot.get('news_signal', '中性')}新闻叠加 {weak_spot.get('macro_signal', '中性')} 宏观环境。"
                ),
                "tone": "down",
            }
        )
    return drivers[:4]


def build_strategy_views(
    holdings: list[dict[str, Any]],
    macro_bundle: dict[str, Any],
    total_financing_hkd: float,
    total_derivative_notional_hkd: float,
    total_nav_hkd: float,
) -> list[dict[str, str]]:
    quality_weight = sum(item["weight_pct"] for item in holdings if item["fundamental_score"] >= 4)
    repair_weight = sum(item["weight_pct"] for item in holdings if item["style"] in {"turnaround", "platform"})
    tactical_weight = sum(item["weight_pct"] for item in holdings if item["style"] in {"leveraged", "speculative", "crypto_beta"})
    trend_up = sum(item["weight_pct"] for item in holdings if item.get("trend_state") in {"强势上行", "修复抬头"})
    trend_down = sum(item["weight_pct"] for item in holdings if item.get("trend_state") == "弱势下行")
    strongest_macro = macro_bundle.get("topics", [])[:1]
    macro_text = (
        strongest_macro[0].get("headline_cn")
        or (strongest_macro[0].get("headlines") or [{}])[0].get("title", "暂无宏观快照")
    ) if strongest_macro else "暂无宏观快照"
    financing_ratio = safe_pct(total_financing_hkd, total_nav_hkd) or 0.0
    derivative_ratio = safe_pct(total_derivative_notional_hkd, total_nav_hkd) or 0.0
    best_quality = next((item for item in holdings if item["fundamental_score"] >= 4), None)
    repair_names = "、".join([item["name"] for item in holdings if item["style"] in {"turnaround", "platform"}][:3]) or "暂无"
    tactical_names = "、".join([item["name"] for item in holdings if item["style"] in {"leveraged", "speculative", "crypto_beta"}][:3]) or "暂无"
    return [
        {
            "title": "自上而下宏观",
            "tag": "Top-down",
            "tone": "warn" if macro_bundle.get("topics") else "neutral",
            "summary": (
                "先判断利率、贸易、政策与 AI 资本开支，再决定哪些主题值得放大。"
                f"当前一级变量是：{macro_text}"
            ),
        },
        {
            "title": "质量复利",
            "tag": f"权重 {quality_weight:.2f}%",
            "tone": "up" if quality_weight >= 28 else "warn",
            "summary": (
                f"当前强基本面仓位约占 {quality_weight:.2f}%，"
                f"{best_quality['name']} 等资产更适合承担底仓，而不是用交易仓扛净值。"
                if best_quality
                else f"当前强基本面仓位约占 {quality_weight:.2f}%。"
            ),
        },
        {
            "title": "估值修复",
            "tag": f"修复仓 {repair_weight:.2f}%",
            "tone": "warn",
            "summary": f"平台与修复类仓位约 {repair_weight:.2f}%，代表标的包括 {repair_names}；关键不在摊平，而在等盈利与政策共振。",
        },
        {
            "title": "趋势动量",
            "tag": f"顺势 {trend_up:.2f}% / 弱势 {trend_down:.2f}%",
            "tone": "up" if trend_up >= trend_down else "warn",
            "summary": "趋势强弱决定执行节奏。顺势阶段可以用加减仓管理，弱势阶段不要只看成本线。 ",
        },
        {
            "title": "事件/主题",
            "tag": f"高波动 {tactical_weight:.2f}%",
            "tone": "down" if tactical_weight >= 18 else "warn",
            "summary": f"高波动与杠杆主题仓约 {tactical_weight:.2f}%，目前主要集中在 {tactical_names}，应当只拿交易预算，不拿底仓预算。",
        },
        {
            "title": "风险预算",
            "tag": f"融资 {financing_ratio:.2f}%",
            "tone": "down" if financing_ratio >= 15 or derivative_ratio >= 15 else "up",
            "summary": (
                f"融资约占净资产 {financing_ratio:.2f}% ，衍生品估算名义本金约占 {derivative_ratio:.2f}% ，"
                "需要独立于选股观点单独管理。"
            ),
        },
    ]


def build_risk_flags(
    holdings: list[dict[str, Any]],
    total_nav_hkd: float,
    total_financing_hkd: float,
    total_derivative_notional_hkd: float,
    top5_ratio: float,
) -> list[dict[str, str]]:
    flags: list[dict[str, str]] = []
    largest = holdings[0] if holdings else None
    biggest_loser = min(holdings, key=lambda item: item["statement_pnl_hkd"], default=None)
    financing_ratio = safe_pct(total_financing_hkd, total_nav_hkd) or 0.0
    derivative_ratio = safe_pct(total_derivative_notional_hkd, total_nav_hkd) or 0.0

    if top5_ratio >= 50:
        flags.append(
            {
                "title": "集中度偏高",
                "detail": f"前五大仓位已占股票市值 {top5_ratio:.2f}%，组合波动基本由头部少数资产决定。",
            }
        )
    if largest and largest["weight_pct"] >= 15:
        flags.append(
            {
                "title": "单一仓位偏大",
                "detail": f"{largest['name']} 当前权重 {largest['weight_pct']:.2f}%，单一仓位已经足以改变组合日波动轨迹。",
            }
        )
    if financing_ratio >= 20:
        flags.append(
            {
                "title": "融资占用仍然偏重",
                "detail": f"结单显示融资相关负现金约 HK${total_financing_hkd:,.0f}，约占净资产 {financing_ratio:.2f}%。",
            }
        )
    if derivative_ratio >= 15:
        flags.append(
            {
                "title": "衍生品敞口不可忽视",
                "detail": f"卖 Put 与 FCN 估算名义本金约 HK${total_derivative_notional_hkd:,.0f}，约占净资产 {derivative_ratio:.2f}%。",
            }
        )
    if biggest_loser and biggest_loser["statement_pnl_hkd"] < -500000:
        flags.append(
            {
                "title": "最大亏损仓仍未出清",
                "detail": (
                    f"{biggest_loser['name']} 当前浮亏约 HK${abs(biggest_loser['statement_pnl_hkd']):,.0f}，"
                    "继续重仓会拖累整个账户的再配置能力。"
                ),
            }
        )
    return flags


def diagnose_holding(holding: dict[str, Any]) -> dict[str, Any]:
    playbook = ACTION_PLAYBOOK.get(holding["symbol"], {})
    role = playbook.get("role") or holding["style_label"]
    stance = playbook.get("stance")
    if not stance:
        if holding["style"] == "leveraged":
            stance = "只做交易仓"
        elif holding["weight_pct"] >= 8 and (holding["statement_pnl_pct"] or 0.0) < -20:
            stance = "减仓降风险"
        elif holding["fundamental_score"] >= 4 and holding["weight_pct"] <= 8:
            stance = "观察持有"
        else:
            stance = "继续跟踪"
    if holding.get("cached_action") == "分批关注" and stance in {"继续跟踪", "观察持有", "谨慎观察"}:
        stance = "分批关注"
    elif holding.get("cached_action") == "持有观察" and stance == "继续跟踪":
        stance = "观察持有"
    elif holding.get("cached_action") == "减仓控制" and stance not in {"反弹减仓", "减仓降风险", "优先清理尾部"}:
        stance = "减仓降风险"
    if holding.get("macro_score", 0) <= -2 and stance in {"继续跟踪", "观察持有"}:
        stance = "谨慎观察"
    if (
        holding.get("current_price") is not None
        and holding.get("ma20") is not None
        and holding.get("ma60") is not None
        and holding["current_price"] < holding["ma20"] < holding["ma60"]
        and holding["style"] in {"leveraged", "speculative", "crypto_beta"}
        and stance not in {"反弹减仓", "减仓降风险", "只做交易仓", "优先清理尾部"}
    ):
        stance = "减仓降风险"
    risk = playbook.get("risk") or holding["fundamental_note"]
    if holding["statement_pnl_pct"] is not None and holding["statement_pnl_pct"] <= -40:
        risk = f"当前浮亏 {holding['statement_pnl_pct']:.2f}%，继续加仓需要极高把握。"
    if holding.get("macro_score", 0) <= -2:
        risk = f"{risk} 当前宏观新闻面对该主题偏逆风。"
    elif holding.get("macro_score", 0) >= 2:
        risk = f"{risk} 当前宏观新闻面对该主题偏顺风。"
    if holding.get("news_signal") in {"偏空", "显著偏空"}:
        risk = f"{risk} 个股新闻流也偏谨慎。"
    action = playbook.get("action")
    if not action:
        if stance in {"减仓降风险", "反弹减仓"}:
            action = "优先处理仓位结构，不再用摊平去解决结构性问题。"
        elif stance == "只做交易仓":
            action = "把它从中长期仓位账本里剥离，单独管理止损与持有期限。"
        else:
            action = "维持当前仓位级别，围绕验证指标和风险预算动态调整。"
    if holding.get("cached_summary") and holding.get("cached_action") in {"分批关注", "持有观察"} and "当前盘面信号" not in action:
        action = f"{action} 当前盘面信号提示：{holding['cached_summary']}"
    if (
        holding.get("current_price") is not None
        and holding.get("ma20") is not None
        and holding.get("ma60") is not None
        and holding["current_price"] >= holding["ma20"] >= holding["ma60"]
    ):
        action = f"{action} 当前价格位于 20/60 日均线上方，可把加减仓节奏建立在趋势未破坏的前提下。"
    elif (
        holding.get("current_price") is not None
        and holding.get("ma20") is not None
        and holding.get("ma60") is not None
        and holding["current_price"] < holding["ma20"] < holding["ma60"]
    ):
        action = f"{action} 当前价格仍在 20/60 日均线下方，弱趋势里不建议只凭成本线做决策。"
    thesis = holding["business_note"]
    if holding.get("cached_summary"):
        thesis = f"{holding['business_note']} 当前信号：{holding['cached_summary']}"
    return {
        "symbol": holding["symbol"],
        "name": holding["name"],
        "weight_pct": holding["weight_pct"],
        "role": role,
        "stance": stance,
        "thesis": thesis,
        "watch_items": holding["watch_items"],
        "risk": risk,
        "action": action,
        "current_price": holding.get("current_price"),
        "change_pct": holding.get("change_pct"),
        "position_label": holding.get("position_label"),
        "trend_state": holding.get("trend_state"),
        "macro_signal": holding.get("macro_signal"),
        "news_signal": holding.get("news_signal"),
        "fundamental_label": holding.get("fundamental_label"),
        "signal_score": holding.get("signal_score"),
        "signal_zone": holding.get("signal_zone"),
        "statement_pnl_pct": holding["statement_pnl_pct"],
        "statement_value_hkd": holding["statement_value_hkd"],
        "category_name": holding["category_name"],
    }


def build_priority_actions(
    holdings: list[dict[str, Any]],
    trades: list[dict[str, Any]],
    total_financing_hkd: float,
    total_derivative_notional_hkd: float,
    total_nav_hkd: float,
    macro_topics: list[dict[str, Any]],
) -> list[dict[str, str]]:
    actions: list[dict[str, str]] = []
    by_symbol = {item["symbol"]: item for item in holdings}
    holding_notes = {item["symbol"]: diagnose_holding(item) for item in holdings}
    trade_snapshot = build_trade_behavior_snapshot(trades, holdings)
    top_macro = max(
        macro_topics,
        key=lambda item: (
            {"高": 3, "中": 2, "低": 1}.get(item["severity"], 0),
            item.get("impact_weight_pct", 0.0),
        ),
        default=None,
    )
    pressure_holding = next(
        (
            item
            for item in sorted(holdings, key=lambda row: (row["weight_pct"], -(row.get("signal_score", 50))), reverse=True)
            if item["weight_pct"] >= 8 and (item.get("signal_score", 50) < 45 or (item.get("statement_pnl_pct") or 0.0) <= -35)
        ),
        None,
    )
    if pressure_holding:
        note = holding_notes[pressure_holding["symbol"]]
        actions.append(
            {
                "title": f"给 {pressure_holding['name']} 设明确的降权窗口",
                "detail": (
                    f"它当前权重 {pressure_holding['weight_pct']:.2f}% ，综合信号 {pressure_holding.get('signal_score', 0)}，"
                    f"趋势 {pressure_holding.get('trend_state', '无数据')}，浮盈亏 {pressure_holding.get('statement_pnl_pct', 0.0):.2f}% 。"
                    f"当前更适合按“{note['stance']}”执行：{note['action']}"
                ),
            }
        )
    repeated_buy_symbols = [symbol for symbol, count in trade_snapshot["buy_symbol_counts"].most_common(3) if count >= 2]
    if repeated_buy_symbols:
        repeated_buy_names = "、".join(unique_strings([by_symbol.get(symbol, {}).get("name", symbol) for symbol in repeated_buy_symbols], limit=3))
        repeated_buy_count = sum(trade_snapshot["buy_symbol_counts"][symbol] for symbol in repeated_buy_symbols)
        macro_text = (
            f" 同时要把“{top_macro['name']}”当成前置条件。"
            if top_macro and any(by_symbol.get(symbol, {}).get("category") in top_macro.get("impact_categories", []) for symbol in repeated_buy_symbols)
            else ""
        )
        actions.append(
            {
                "title": f"暂停继续在 {repeated_buy_names} 上叠加同方向风险",
                "detail": (
                    f"最近交易里 {repeated_buy_names} 被连续买入 {repeated_buy_count} 笔。"
                    "除非你明确把它们归为短线交易仓，否则先暂停继续加码，避免把弹性仓一路抬成组合主风险。"
                    f"{macro_text}"
                ),
            }
        )
    crypto_names = [symbol for symbol in ("MSTR", "BMNR", "COIN", "CRCL", "IREN") if symbol in by_symbol]
    if crypto_names:
        crypto_weight = sum(by_symbol[symbol]["weight_pct"] for symbol in crypto_names)
        crypto_name_text = "、".join(unique_strings([by_symbol[symbol]["name"] for symbol in crypto_names], limit=5))
        actions.append(
            {
                "title": "把 Crypto 相关仓并成一个风险桶",
                "detail": (
                    f"{crypto_name_text} 合计约 {crypto_weight:.2f}% 权重。"
                    "如果再叠加卖 Put、FCN 或其他结构性产品，同一个因子会在多个账户重复放大，"
                    "下一步优先做的是削减重复暴露，而不是继续摊到更多相关标的。"
                ),
            }
        )
    financing_ratio = safe_pct(total_financing_hkd, total_nav_hkd) or 0.0
    derivative_ratio = safe_pct(total_derivative_notional_hkd, total_nav_hkd) or 0.0
    if financing_ratio >= 15 or derivative_ratio >= 15:
        actions.append(
            {
                "title": "先把融资和结构性产品压回主动区间",
                "detail": (
                    f"当前融资约占净资产 {financing_ratio:.2f}%，衍生品估算名义本金约占 {derivative_ratio:.2f}% 。"
                    "这已经决定了你很难从容调仓。先恢复主动权，再谈提高赔率。"
                ),
            }
        )
    quality_candidates = [
        item
        for item in sorted(holdings, key=lambda row: (row.get("signal_score", 0), row["fundamental_score"], -row["weight_pct"]), reverse=True)
        if item["fundamental_score"] >= 4 and item.get("signal_score", 0) >= 68 and item["style"] not in {"leveraged", "speculative", "crypto_beta"}
    ]
    if quality_candidates:
        quality_names = "、".join(unique_strings([item["name"] for item in quality_candidates], limit=3))
        macro_clause = (
            f" 在“{top_macro['name']}”影响未缓和前，新增预算尤其只该给这些质量更高、验证更清晰的仓位。"
            if top_macro and top_macro.get("impact_weight_pct", 0.0) >= 20
            else ""
        )
        actions.append(
            {
                "title": f"释放出的预算只补到 {quality_names}",
                "detail": (
                    f"如果你需要重新部署资金，优先考虑 {quality_names} 这类基本面和综合信号都更强的仓位，"
                    "不要再平均撒向修复仓、杠杆工具和高波动主题。"
                    f"{macro_clause}"
                ),
            }
        )
    return actions[:5]


def holding_size_bucket(weight_pct: float) -> str:
    if weight_pct >= 12:
        return "超配核心"
    if weight_pct >= 6:
        return "核心持仓"
    if weight_pct >= 2:
        return "卫星配置"
    return "观察仓"


def split_watch_items(text: str) -> list[str]:
    return [item.strip() for item in re.split(r"[、,，/]+", text) if item.strip()]


def factor_signal_comment(label: str, score: int) -> str:
    if label == "基本面":
        return {
            2: "基本面质量在组合里属于第一梯队。",
            1: "基本面仍站得住，但还不够强到无视估值与节奏。",
            0: "基本面中性，需要靠趋势或催化配合。",
            -1: "基本面容错率偏低，不适合重仓。",
            -2: "基本面支撑弱，仓位只能轻。",
        }.get(score, "基本面维度暂无结论。")
    if label == "趋势":
        return {
            2: "价格结构强，适合把执行节奏建立在趋势未破坏上。",
            1: "趋势正在修复，但还没到可以大幅激进的时候。",
            0: "趋势未给出方向，需要等待确认。",
            -1: "趋势转弱，反弹更适合做结构调整。",
            -2: "趋势明显偏弱，不宜只看成本线。",
        }.get(score, "趋势维度暂无结论。")
    if label == "新闻":
        return {
            2: "近期新闻流明显偏正面，利于强化市场预期。",
            1: "近期新闻略偏正面，但仍需业绩或数据验证。",
            0: "新闻流中性，对价格影响有限。",
            -1: "新闻流偏谨慎，情绪面会拖累估值。",
            -2: "新闻流明显偏空，容易压制风险偏好。",
        }.get(score, "新闻维度暂无结论。")
    if label == "宏观":
        return {
            2: "宏观环境对该主题形成顺风。",
            1: "宏观环境略有支持，但强度有限。",
            0: "宏观环境未构成明确顺风或逆风。",
            -1: "宏观环境略偏逆风，节奏要保守。",
            -2: "宏观环境明确逆风，执行上应先控风险。",
        }.get(score, "宏观维度暂无结论。")
    return {
        2: "风险预算允许相对主动。",
        1: "风险可控，但仍需仓位纪律。",
        0: "风险预算中性。",
        -1: "风险开始高于赔率，要保留余地。",
        -2: "风险显著高于赔率，应优先控制敞口。",
    }.get(score, "风控维度暂无结论。")


def build_trade_behavior_snapshot(trades: list[dict[str, Any]], holdings: list[dict[str, Any]]) -> dict[str, Any]:
    recent_trades = trades[:12]
    holding_by_symbol = {item["symbol"]: item for item in holdings}
    buys = [item for item in recent_trades if item["side"] == "买入"]
    sells = [item for item in recent_trades if item["side"] == "卖出"]
    averaging_down = [
        item
        for item in buys
        if (holding_by_symbol.get(item["symbol"], {}).get("statement_pnl_pct") or 0.0) <= -15
    ]
    momentum_adds = [
        item
        for item in buys
        if (holding_by_symbol.get(item["symbol"], {}).get("signal_score") or 0) >= 60
    ]
    high_beta_adds = [
        item
        for item in buys
        if holding_by_symbol.get(item["symbol"], {}).get("style") in {"leveraged", "speculative", "crypto_beta"}
    ]
    theme_counter = Counter(
        holding_by_symbol[item["symbol"]]["category_name"]
        for item in buys
        if item["symbol"] in holding_by_symbol
    )
    dominant_theme = theme_counter.most_common(1)[0][0] if theme_counter else "暂无集中主题"
    buy_symbol_counts = Counter(item["symbol"] for item in buys if item.get("symbol"))
    sell_symbol_counts = Counter(item["symbol"] for item in sells if item.get("symbol"))
    return {
        "recent_trades": recent_trades,
        "buy_count": len(buys),
        "sell_count": len(sells),
        "averaging_down": averaging_down,
        "momentum_adds": momentum_adds,
        "high_beta_adds": high_beta_adds,
        "dominant_theme": dominant_theme,
        "buy_symbol_counts": buy_symbol_counts,
        "sell_symbol_counts": sell_symbol_counts,
        "latest_trade": recent_trades[0] if recent_trades else None,
    }


def fallback_ai_engine_meta() -> dict[str, Any]:
    return {
        "mode": "rules",
        "provider": "local",
        "model": None,
        "label": "组合分析引擎",
        "note": "AI 洞察会结合持仓、交易、走势和市场主题生成组合提示。",
    }


def empty_ai_insights() -> dict[str, Any]:
    return {
        "headline": "",
        "deep_summary": "",
        "cards": [],
        "playbook": [],
        "sections": [],
        "position_actions": [],
        "engine": fallback_ai_engine_meta(),
    }


def build_default_deep_summary(rule_based: dict[str, Any]) -> str:
    headline = rule_based.get("headline") or ""
    first_card = (rule_based.get("cards") or [{}])[0].get("detail") or ""
    first_action = (rule_based.get("playbook") or [""])[0]
    summary = " ".join(part for part in [headline, first_card, first_action] if part).strip()
    return summary[:420]


def pick_ai_focus_holdings(holdings: list[dict[str, Any]], trades: list[dict[str, Any]]) -> list[dict[str, Any]]:
    trade_symbols = {item["symbol"] for item in trades[:10] if item.get("symbol")}
    selected: list[dict[str, Any]] = []
    seen: set[str] = set()
    candidate_groups = [
        holdings[:8],
        [item for item in holdings if item["symbol"] in trade_symbols],
        [item for item in holdings if item["style"] in {"leveraged", "speculative", "crypto_beta"}],
        [
            item
            for item in holdings
            if item["weight_pct"] >= 4 and (item.get("signal_score", 50) < 48 or (item.get("statement_pnl_pct") or 0.0) <= -25)
        ],
        [
            item
            for item in holdings
            if item["fundamental_score"] >= 4 and item.get("signal_score", 0) >= 68 and item["style"] not in {"leveraged", "speculative", "crypto_beta"}
        ],
    ]
    for group in candidate_groups:
        for item in group:
            if item["symbol"] in seen:
                continue
            seen.add(item["symbol"])
            selected.append(item)
            if len(selected) >= 6:
                return selected
    return selected


def build_rule_sections(
    holdings: list[dict[str, Any]],
    focus_holdings: list[dict[str, Any]],
    trade_snapshot: dict[str, Any],
    pressure_holding: dict[str, Any] | None,
    top_macro: dict[str, Any] | None,
    macro_affected_names: str,
    theme_names: str,
    financing_ratio: float,
    derivative_ratio: float,
    repeat_add_names: str,
    high_beta_names: str,
    quality_redeploy_names: str,
) -> list[dict[str, Any]]:
    top_weight_names = "、".join(unique_strings([item["name"] for item in holdings[:4]], limit=4)) or "暂无"
    weak_news_names = (
        "、".join(
            unique_strings(
                [item["name"] for item in focus_holdings if item.get("news_signal") in {"偏空", "显著偏空"}],
                limit=4,
            )
        )
        or "暂无"
    )
    sections = [
        {
            "title": "组合结构诊断",
            "summary": (
                f"组合净值目前主要由 {top_weight_names} 这些头部仓位驱动，主线集中在 {theme_names}。"
                + (
                    f" {pressure_holding['name']} 是当前最需要先处理的弱信号大仓。"
                    if pressure_holding
                    else " 当前没有单一仓位形成绝对拖累，但集中度依然偏高。"
                )
            ),
            "bullets": [
                f"头部仓位决定了大部分净值弹性，分散化的关键不在持仓数量，而在是否共享同一宏观驱动。",
                f"新增预算优先考虑 {quality_redeploy_names} 这类“基本面更强 + 信号更好”的仓位，而不是平均摊给修复仓。",
                (
                    f"{pressure_holding['name']} 继续占用大仓位，会直接拖慢组合再配置。"
                    if pressure_holding
                    else "当前组合更像集中型表达，后续资金分配要避免进一步堆在同一条主线上。"
                ),
            ],
        },
        {
            "title": "宏观与新闻传导",
            "summary": (
                f"当前最重要的外部变量是“{top_macro['name']}”，它影响的组合权重约 {top_macro.get('impact_weight_pct', 0.0):.2f}% 。"
                if top_macro
                else "当前宏观主题没有单一压倒性变量，但多个主题仍可能在风险偏好收缩时同步承压。"
            ),
            "bullets": [
                (
                    f"受该变量影响最大的仓位包括 {macro_affected_names}，处理优先级要高于单只股票故事。"
                    if top_macro
                    else f"需要持续跟踪新闻流偏弱的仓位，当前明显偏弱的包括 {weak_news_names}。"
                ),
                f"当前个股新闻流偏弱的重点仓包括 {weak_news_names}，这会削弱纯靠估值修复的胜率。",
                "宏观主题、个股新闻和趋势信号如果同时朝同一个方向走，组合回撤会被放大；这比单一利空更值得警惕。",
            ],
        },
        {
            "title": "交易与杠杆路径",
            "summary": (
                f"最近交易的新增风险主要落在 {repeat_add_names}，融资占净资产 {financing_ratio:.2f}% ，衍生品名义本金占 {derivative_ratio:.2f}% 。"
            ),
            "bullets": [
                (
                    "最近存在逆势补仓迹象，说明交易纪律容易被成本线牵引。"
                    if trade_snapshot["averaging_down"]
                    else "最近交易没有明显失控，但仍需明确区分底仓、交易仓和修复仓。"
                ),
                (
                    f"高波动风险主要集中在 {high_beta_names}，这些仓位不能和核心底仓使用同一套持有规则。"
                    if high_beta_names != "暂无"
                    else "当前高波动工具仓不算极端，但杠杆与交易频率仍要单独管理。"
                ),
                "一旦宏观逆风和弱趋势叠加，杠杆、衍生品和高 beta 仓位会先放大回撤，再压缩你对优质资产的加仓空间。",
            ],
        },
        {
            "title": "下一周执行框架",
            "summary": "下周的核心不是继续找新故事，而是先把仓位分层、资金来源和验证节点重新排清楚。",
            "bullets": [
                (
                    f"先处理 {pressure_holding['name']} 这类弱信号大仓，再讨论新增分配。"
                    if pressure_holding
                    else "先定义哪些仓位能承担底仓任务，哪些只能留在观察仓或交易仓。"
                ),
                f"新增预算优先留给 {quality_redeploy_names}，不要再平均撒向高波动修复仓。",
                "每笔新增仓都要绑定验证指标和失效条件，否则交易动作会不自觉演变成被动摊平。",
            ],
        },
    ]
    return sections


def build_rule_position_actions(focus_holdings: list[dict[str, Any]]) -> list[dict[str, str]]:
    actions: list[dict[str, str]] = []
    for item in focus_holdings[:8]:
        detail = fundamental_details_for_holding(item)
        diagnosis = diagnose_holding(item)
        trigger_parts = [detail["catalyst"]]
        if item.get("trend_state"):
            trigger_parts.append(f"当前趋势 {item['trend_state']}")
        if item.get("news_headline"):
            trigger_parts.append(f"最新新闻线索：{item['news_headline']}")
        actions.append(
            {
                "symbol": item["symbol"],
                "name": item["name"],
                "stance": diagnosis.get("stance") or "继续跟踪",
                "thesis": f"{detail['business_model']} 当前最关键的盈利验证点是：{detail['earnings_driver']}",
                "trigger": "；".join(part for part in trigger_parts if part)[:220],
                "risk": (diagnosis.get("risk") or detail["red_flags"])[:220],
                "action": (diagnosis.get("action") or "围绕验证指标和风险预算动态调整。")[:240],
            }
        )
    return actions


def enhance_ai_insights(
    rule_based: dict[str, Any],
    diagnostic_payload: dict[str, Any],
    ai_request_config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    overlay = generate_ai_overlay(diagnostic_payload, ai_request_config=ai_request_config)
    merged = {
        **rule_based,
        "engine": overlay.get("engine") or fallback_ai_engine_meta(),
        "deep_summary": build_default_deep_summary(rule_based),
    }
    if overlay.get("ok"):
        if overlay.get("headline"):
            merged["headline"] = overlay["headline"]
        if overlay.get("cards"):
            merged["cards"] = overlay["cards"]
        if overlay.get("playbook"):
            merged["playbook"] = overlay["playbook"]
        if overlay.get("deep_summary"):
            merged["deep_summary"] = overlay["deep_summary"]
        if overlay.get("sections"):
            merged["sections"] = overlay["sections"]
        if overlay.get("position_actions"):
            merged["position_actions"] = overlay["position_actions"]
    return merged


def build_default_stock_detail_ai(
    target: dict[str, Any],
    detail: dict[str, str],
    holding_note: dict[str, Any],
    executive_summary: list[str],
    bull_case: list[str],
    bear_case: list[str],
    watchlist: list[str],
    action_plan: list[str],
    latest_trade: dict[str, Any] | None,
) -> dict[str, Any]:
    trade_line = (
        f"最近一次相关交易是 {latest_trade['date']} 的“{latest_trade['side']}”，需要和当前持仓定位一起看。"
        if latest_trade
        else "近期没有直接交易记录，更适合围绕验证指标与风险预算做动作。"
    )
    return {
        "headline": f"{target['name']} 当前最关键的矛盾，是“{holding_note['stance']}”与 {target.get('trend_state', '无数据')} 之间是否匹配。",
        "deep_summary": " ".join(executive_summary[:3])[:420],
        "executive_summary": executive_summary[:4],
        "sections": [
            {
                "title": "业务与催化",
                "summary": f"{detail['business_model']} 当前最关键的盈利验证点是：{detail['earnings_driver']}",
                "bullets": [detail["catalyst"], detail["valuation_anchor"]],
            },
            {
                "title": "盘面与交易",
                "summary": (
                    f"当前处于 {target.get('trend_state', '无数据')} / {target.get('position_label', '无数据')}，"
                    f"新闻流 {target.get('news_signal', '中性')}，宏观环境 {target.get('macro_signal', '中性')}。"
                ),
                "bullets": [holding_note["action"], trade_line],
            },
            {
                "title": "风险与执行",
                "summary": holding_note["risk"],
                "bullets": [detail["red_flags"], action_plan[0] if action_plan else "围绕验证指标和风险预算动态调整。"],
            },
        ],
        "bull_case": bull_case[:3],
        "bear_case": bear_case[:3],
        "watchlist": watchlist[:6],
        "action_plan": action_plan[:4],
        "engine": fallback_ai_engine_meta(),
    }


def enhance_stock_detail_ai(
    default_ai: dict[str, Any],
    diagnostic_payload: dict[str, Any],
    ai_request_config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    overlay = generate_stock_detail_overlay(diagnostic_payload, ai_request_config=ai_request_config)
    merged = {**default_ai, "engine": overlay.get("engine") or fallback_ai_engine_meta()}
    if overlay.get("ok"):
        for key in ["headline", "deep_summary", "executive_summary", "sections", "bull_case", "bear_case", "watchlist", "action_plan"]:
            if overlay.get(key):
                merged[key] = overlay[key]
    return merged


def build_ai_insights(
    holdings: list[dict[str, Any]],
    trades: list[dict[str, Any]],
    derivatives: list[dict[str, Any]],
    total_nav_hkd: float,
    total_financing_hkd: float,
    total_derivative_notional_hkd: float,
    macro_topics: list[dict[str, Any]],
    ai_request_config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    trade_snapshot = build_trade_behavior_snapshot(trades, holdings)
    holding_by_symbol = {item["symbol"]: item for item in holdings}
    top_holdings = holdings[:5]
    theme_names = "、".join(unique_strings([item["category_name"] for item in top_holdings], limit=3)) or "多主题"
    core_names = (
        "、".join(
            unique_strings(
                [item["name"] for item in sorted(holdings, key=lambda row: (row.get("signal_score", 0), row["weight_pct"]), reverse=True)
                 if item["fundamental_score"] >= 4 and item.get("signal_score", 0) >= 60],
                limit=3,
            )
        )
        or "暂无"
    )
    high_beta_names = (
        "、".join(unique_strings([item["name"] for item in holdings if item["style"] in {"leveraged", "speculative", "crypto_beta"}], limit=4))
        or "暂无"
    )
    financing_ratio = safe_pct(total_financing_hkd, total_nav_hkd) or 0.0
    derivative_ratio = safe_pct(total_derivative_notional_hkd, total_nav_hkd) or 0.0
    pressure_holding = next(
        (
            item
            for item in sorted(holdings, key=lambda row: row["weight_pct"], reverse=True)
            if item["weight_pct"] >= 8 and (item.get("signal_score", 50) < 45 or (item.get("statement_pnl_pct") or 0.0) <= -35)
        ),
        None,
    )
    repeat_add_names = "、".join(
        unique_strings(
            [
                holding_by_symbol.get(symbol, {}).get("name", symbol)
                for symbol, count in trade_snapshot["buy_symbol_counts"].most_common(4)
                if count >= 1
            ],
            limit=4,
        )
    ) or "暂无"
    high_beta_add_names = "、".join(
        unique_strings([holding_by_symbol.get(item["symbol"], {}).get("name", item["symbol"]) for item in trade_snapshot["high_beta_adds"]], limit=4)
    ) or "暂无"
    quality_redeploy_names = (
        "、".join(
            unique_strings(
                [
                    item["name"]
                    for item in sorted(holdings, key=lambda row: (row.get("signal_score", 0), row["fundamental_score"], -row["weight_pct"]), reverse=True)
                    if item["fundamental_score"] >= 4 and item.get("signal_score", 0) >= 68 and item["style"] not in {"leveraged", "speculative", "crypto_beta"}
                ],
                limit=3,
            )
        )
        or core_names
    )
    macro_affected_names = "暂无"
    top_macro = max(
        macro_topics,
        key=lambda item: (
            {"高": 3, "中": 2, "低": 1}.get(item["severity"], 0),
            abs(item.get("score", 0)),
            item.get("impact_weight_pct", 0.0),
        ),
        default=None,
    )
    if top_macro:
        macro_affected_names = (
            "、".join(
                unique_strings(
                    [item["name"] for item in holdings if item["category"] in top_macro.get("impact_categories", [])],
                    limit=4,
                )
            )
            or "暂无"
        )
    headline = (
        f"这套组合当前真正决定净值弹性的，不只是 {theme_names} 这些主线本身，"
        "而是你是否把弱信号大仓、近期新增交易和杠杆/衍生品暴露拆开管理。"
    )
    cards = [
        (
            {
                "title": "最大仓位拖累点",
                "tone": "down",
                "detail": (
                    f"{pressure_holding['name']} 当前权重 {pressure_holding['weight_pct']:.2f}% ，综合信号 {pressure_holding.get('signal_score', 0)}，"
                    f"趋势 {pressure_holding.get('trend_state', '无数据')}，浮盈亏 {pressure_holding.get('statement_pnl_pct', 0.0):.2f}% 。"
                    "它已经不只是观点仓，而是会直接拖慢再配置节奏的净值约束项。"
                ),
            }
            if pressure_holding
            else {
                "title": "组合结构画像",
                "tone": "warn",
                "detail": (
                    f"当前头部仓位把组合重心放在 {theme_names}，说明少数核心观点在驱动大部分净值。"
                    "一旦这些观点同时受同一宏观变量影响，波动会被同步放大。"
                ),
            }
        ),
        {
            "title": "最近交易把风险往哪里推",
            "tone": "down" if trade_snapshot["averaging_down"] or trade_snapshot["high_beta_adds"] else "up",
            "detail": (
                f"最近 {len(trade_snapshot['recent_trades'])} 笔交易里，买入 {trade_snapshot['buy_count']} 笔、卖出 {trade_snapshot['sell_count']} 笔，"
                f"新增风险主要打在 {repeat_add_names}。"
                f"{' 存在逆势补仓迹象。' if trade_snapshot['averaging_down'] else ''}"
                f"{' 同时继续给高波动仓加码，代表标的是 ' + high_beta_add_names + '。' if trade_snapshot['high_beta_adds'] else ''}"
            ),
        },
        {
            "title": "风险传导链条",
            "tone": "down" if financing_ratio >= 15 or derivative_ratio >= 15 else "warn",
            "detail": (
                f"融资约占净资产 {financing_ratio:.2f}%，衍生品名义本金约占 {derivative_ratio:.2f}%，"
                f"高波动仓主要集中在 {high_beta_names}。"
                + (
                    f" 同时“{top_macro['name']}”影响的持仓约 {top_macro.get('impact_weight_pct', 0.0):.2f}% ，代表仓位包括 {macro_affected_names}。"
                    if top_macro
                    else ""
                )
                + "这意味着方向判断一旦失效，回撤不会只出现在一个模块。"
            ),
        },
        {
            "title": "下一笔资金该落到哪里",
            "tone": "up",
            "detail": (
                f"新增预算只值得留给 {quality_redeploy_names} 这类基本面和综合信号都更强的仓位。"
                + (f" 先处理 {pressure_holding['name']} 这类弱信号大仓，再谈新增分配。" if pressure_holding else "")
            ),
        },
    ]
    playbook = []
    if pressure_holding:
        playbook.append(
            f"{pressure_holding['name']} 先只做降权/控仓，不再新增摊平；只有当趋势从“{pressure_holding.get('trend_state', '无数据')}”修复且基本面验证改善时，才讨论加回。"
        )
    if trade_snapshot["buy_count"]:
        playbook.append(
            f"最近新增仓位主要打在 {repeat_add_names}；下一次下单前先确认这些仓位究竟归属底仓、修复仓还是交易仓，不再混用同一套持仓逻辑。"
        )
    if top_macro:
        playbook.append(
            f"未来一周把“{top_macro['name']}”当一级变量，受影响最大的 {macro_affected_names} 要统一节奏处理，动作优先级高于单只股票故事。"
        )
    if financing_ratio >= 15 or derivative_ratio >= 15:
        playbook.append(
            f"融资/衍生品暴露还在高位，先把总风险预算往下压，再把释放出来的仓位转给 {quality_redeploy_names} 这类更能承担底仓任务的资产。"
        )
    else:
        playbook.append(f"新增风险预算优先留给 {quality_redeploy_names}，不要再平均撒向修复仓和高波动工具仓。")
    if trade_snapshot["averaging_down"]:
        playbook.append("逆势补仓必须带失败条件和退出条件，否则很容易把交易动作升级成结构性错误。")
    if top_macro:
        playbook = playbook[:5]
    focus_holdings = pick_ai_focus_holdings(holdings, trades)
    rule_based = {
        "headline": headline,
        "cards": cards,
        "playbook": playbook,
        "sections": build_rule_sections(
            holdings,
            focus_holdings,
            trade_snapshot,
            pressure_holding,
            top_macro,
            macro_affected_names,
            theme_names,
            financing_ratio,
            derivative_ratio,
            repeat_add_names,
            high_beta_names,
            quality_redeploy_names,
        ),
        "position_actions": build_rule_position_actions(focus_holdings),
    }
    diagnostic_payload = {
        "summary": {
            "total_nav_hkd": round(total_nav_hkd, 2),
            "financing_ratio_pct": round(financing_ratio, 2),
            "derivative_ratio_pct": round(derivative_ratio, 2),
            "top_theme_names": theme_names,
            "core_names": core_names,
            "high_beta_names": high_beta_names,
            "repeat_add_names": repeat_add_names,
            "quality_redeploy_names": quality_redeploy_names,
            "top_macro_name": top_macro.get("name") if top_macro else None,
            "top_macro_weight_pct": top_macro.get("impact_weight_pct") if top_macro else None,
            "macro_affected_names": macro_affected_names,
        },
        "top_holdings": [
            {
                "symbol": item["symbol"],
                "name": item["name"],
                "weight_pct": item["weight_pct"],
                "statement_pnl_pct": item.get("statement_pnl_pct"),
                "signal_score": item.get("signal_score"),
                "signal_zone": item.get("signal_zone"),
                "trend_state": item.get("trend_state"),
                "macro_signal": item.get("macro_signal"),
                "news_signal": item.get("news_signal"),
                "style_label": item.get("style_label"),
                "category_name": item.get("category_name"),
                "fundamental_label": item.get("fundamental_label"),
            }
            for item in holdings[:6]
        ],
        "focus_holdings": [
            {
                "symbol": item["symbol"],
                "name": item["name"],
                "weight_pct": item["weight_pct"],
                "statement_pnl_pct": item.get("statement_pnl_pct"),
                "signal_score": item.get("signal_score"),
                "signal_zone": item.get("signal_zone"),
                "trend_state": item.get("trend_state"),
                "position_label": item.get("position_label"),
                "macro_signal": item.get("macro_signal"),
                "news_signal": item.get("news_signal"),
                "news_headline": item.get("news_headline"),
                "style_label": item.get("style_label"),
                "category_name": item.get("category_name"),
                "fundamental_label": item.get("fundamental_label"),
                "risk_level": item.get("risk_level"),
                "role": diagnose_holding(item).get("role"),
                "stance": diagnose_holding(item).get("stance"),
                "action_seed": diagnose_holding(item).get("action"),
                "fundamentals": {
                    key: value
                    for key, value in fundamental_details_for_holding(item).items()
                    if key in {"business_model", "earnings_driver", "valuation_anchor", "catalyst", "red_flags"}
                },
            }
            for item in focus_holdings[:4]
        ],
        "trade_snapshot": {
            "buy_count": trade_snapshot["buy_count"],
            "sell_count": trade_snapshot["sell_count"],
            "dominant_theme": trade_snapshot["dominant_theme"],
            "averaging_down_symbols": [item["symbol"] for item in trade_snapshot["averaging_down"][:5]],
            "high_beta_add_symbols": [item["symbol"] for item in trade_snapshot["high_beta_adds"][:5]],
        },
        "recent_trades": [
            {
                "date": item["date"],
                "symbol": item["symbol"],
                "name": item["name"],
                "side": item["side"],
                "price": item.get("price"),
                "currency": item.get("currency"),
                "broker": item.get("broker"),
                "current_role": diagnose_holding(holding_by_symbol[item["symbol"]]).get("role") if item["symbol"] in holding_by_symbol else None,
            }
            for item in trades[:6]
        ],
        "macro_topics": [
            {
                "name": item.get("name"),
                "severity": item.get("severity"),
                "score": item.get("score"),
                "impact_weight_pct": item.get("impact_weight_pct"),
                "headline": item.get("headline"),
                "summary": item.get("summary"),
                "impact_labels": item.get("impact_labels"),
            }
            for item in macro_topics[:3]
        ],
        "derivatives": [
            {
                "symbol": item.get("symbol"),
                "description": item.get("description"),
                "estimated_notional_hkd": item.get("estimated_notional_hkd"),
                "underlyings": item.get("underlyings"),
                "broker": item.get("broker"),
            }
            for item in derivatives[:4]
        ],
        "derivative_count": len(derivatives),
        "rule_based": {
            "headline": rule_based["headline"],
            "cards": rule_based["cards"],
            "playbook": rule_based["playbook"],
        },
    }
    return enhance_ai_insights(rule_based, diagnostic_payload, ai_request_config=ai_request_config)


def refresh_holding_market_state(
    holding: dict[str, Any],
    live_row: dict[str, Any] | None,
    analysis_date_cn: str | None,
) -> dict[str, Any]:
    live_row = live_row or {}
    current_price = live_row.get("current_price")
    price_source = holding.get("price_source", "statement")
    market_data_source = live_row.get("market_data_source") or holding.get("market_data_source")
    if live_row.get("history"):
        price_source = "network"
    elif live_row.get("current_price") is not None:
        price_source = "cache"
    if current_price is None:
        current_price = holding.get("current_price")
    if current_price is None:
        current_price = holding.get("statement_price")
        price_source = "statement"
        market_data_source = "statement"
    elif price_source == "cache" and market_data_source is None:
        market_data_source = "cache"
    ma20 = live_row.get("ma20", holding.get("ma20"))
    ma60 = live_row.get("ma60", holding.get("ma60"))
    position_label = live_row.get("position_label") or holding.get("position_label") or "无数据"
    trend_state = infer_trend_state(current_price, ma20, ma60, holding.get("cached_reasons") or [])
    refreshed = {
        **holding,
        "live_available": bool(live_row) or holding.get("live_available", False),
        "current_price": current_price,
        "trade_date": live_row.get("trade_date") or holding.get("trade_date") or analysis_date_cn,
        "change_pct": live_row.get("change_pct", holding.get("change_pct")),
        "change_pct_5d": live_row.get("change_pct_5d", holding.get("change_pct_5d")),
        "ma20": ma20,
        "ma60": ma60,
        "range_position_60d": live_row.get("range_position_60d", holding.get("range_position_60d")),
        "position_label": position_label,
        "trend_state": trend_state,
        "history": live_row.get("history") or holding.get("history", []),
        "normalized_history": live_row.get("normalized_history") or holding.get("normalized_history", []),
        "price_source": price_source,
        "market_data_source": market_data_source,
        "market_source_label": display_price_source_label(price_source, market_data_source),
    }
    factor_scores = dict(holding.get("factor_scores", {}))
    factor_scores["fundamental"] = factor_scores.get("fundamental", factor_score_bucket(int(refreshed.get("fundamental_score", 3)) - 3))
    factor_scores["trend"] = trend_factor_score(trend_state)
    factor_scores["news"] = factor_scores.get("news", 0)
    factor_scores["macro"] = factor_scores.get("macro", 0)
    factor_scores["risk"] = risk_factor_score(refreshed)
    refreshed["factor_scores"] = factor_scores
    refreshed["signal_score"] = composite_signal_score(
        factor_scores["fundamental"],
        factor_scores["trend"],
        factor_scores["news"],
        factor_scores["macro"],
        factor_scores["risk"],
    )
    refreshed["signal_zone"] = signal_zone(refreshed["signal_score"])
    return refreshed


def build_detail_signal_matrix(target: dict[str, Any], peers: list[dict[str, Any]]) -> dict[str, Any]:
    columns = [
        {"key": "fundamental", "label": "基本面"},
        {"key": "trend", "label": "趋势"},
        {"key": "news", "label": "新闻"},
        {"key": "macro", "label": "宏观"},
        {"key": "risk", "label": "风控"},
    ]
    rows = []
    for item in [target, *peers]:
        rows.append(
            {
                "symbol": item["symbol"],
                "name": item["name"],
                "is_target": item["symbol"] == target["symbol"],
                "signal_score": item.get("signal_score", 50),
                "signal_zone": item.get("signal_zone", "中性跟踪"),
                "trend_state": item.get("trend_state", "无数据"),
                "cells": [
                    {
                        "label": column["label"],
                        "score": item.get("factor_scores", {}).get(column["key"], 0),
                    }
                    for column in columns
                ],
            }
        )
    return {"columns": columns, "rows": rows}


def build_detail_comparison_history(target: dict[str, Any], peers: list[dict[str, Any]]) -> list[dict[str, Any]]:
    target_points = target.get("normalized_history") or []
    if not target_points:
        return []
    rows = [
        {
            "symbol": target["symbol"],
            "name": target["name"],
            "is_target": True,
            "points": target_points,
        }
    ]
    for item in peers:
        points = item.get("normalized_history") or []
        if not points:
            continue
        rows.append(
            {
                "symbol": item["symbol"],
                "name": item["name"],
                "is_target": False,
                "points": points,
            }
        )
    return rows


def build_stock_detail_payload(
    symbol: str,
    force_refresh: bool = False,
    include_live: bool = True,
    allow_cached_fallback: bool = True,
    share_mode: bool = False,
    user_id: str | None = None,
    ai_request_config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    dashboard = build_dashboard_payload(
        force_refresh=force_refresh,
        include_live=False,
        allow_cached_fallback=allow_cached_fallback,
        include_ai=False,
        user_id=user_id,
        refresh_portfolio=False,
    )
    target = next(
        (
            item
            for item in dashboard["holdings"]
            if symbol_matches(item["symbol"], symbol)
        ),
        None,
    )
    if target is None:
        raise KeyError(symbol)

    peer_candidates = [
        item
        for item in dashboard["holdings"]
        if item["category"] == target["category"] and item["symbol"] != target["symbol"]
    ][:3]
    detail_live_bundle = fetch_live_bundle([target], force_refresh=force_refresh, allow_network=include_live)
    peer_live_bundle = (
        fetch_live_bundle(peer_candidates, force_refresh=False, allow_network=False)
        if peer_candidates
        else {"rows_by_symbol": {}, "updated_at": None}
    )
    detail_rows_by_symbol = {
        **peer_live_bundle.get("rows_by_symbol", {}),
        **detail_live_bundle.get("rows_by_symbol", {}),
    }
    target = refresh_holding_market_state(
        target,
        lookup_symbol_value(detail_rows_by_symbol, target["symbol"], {}),
        dashboard["analysis_date_cn"],
    )
    peer_candidates = [
        refresh_holding_market_state(
            item,
            lookup_symbol_value(detail_rows_by_symbol, item["symbol"], {}),
            dashboard["analysis_date_cn"],
        )
        for item in peer_candidates
    ]
    detail = fundamental_details_for_holding(target)
    holding_note = diagnose_holding(target)
    related_trades = [
        item
        for item in dashboard["trades"]
        if symbol_matches(item.get("symbol"), target["symbol"])
    ]
    related_derivatives = [
        item
        for item in dashboard["derivatives"]
        if symbol_matches(item.get("symbol"), target["symbol"])
        or any(symbol_matches(underlying, target["symbol"]) for underlying in item.get("underlyings", []))
    ]
    demo_holdings_by_symbol = {item["symbol"]: item for item in demoize_top_holdings(dashboard["holdings"])}
    target_demo = demo_holdings_by_symbol.get(target["symbol"], {})
    demo_weight_pct = target_demo.get("demo_weight_pct")
    if demo_weight_pct is None:
        demo_weight_pct = share_demo_pct(target.get("weight_pct"), f"share-detail-weight:{target['symbol']}", floor=1.2, ceil=26.0)
    demo_pnl_pct = target_demo.get("demo_pnl_pct")
    if demo_pnl_pct is None:
        demo_pnl_pct = share_demo_pct(target.get("statement_pnl_pct"), f"share-detail-pnl-pct:{target['symbol']}")
    demo_pnl_hkd = share_demo_signed_hkd(target.get("statement_pnl_hkd"), f"share-detail-pnl-hkd:{target['symbol']}")
    demo_avg_cost = share_demo_price(target.get("avg_cost"), f"share-detail-cost:{target['symbol']}")
    account_alias_by_id = {
        account["account_id"]: f"账户 {index}"
        for index, account in enumerate(target.get("accounts", []), start=1)
        if account.get("account_id")
    }
    peers = [
        {
            "symbol": item["symbol"],
            "name": item["name"],
            "signal_score": item.get("signal_score", 50),
            "trend_state": item.get("trend_state"),
            "current_price": item.get("current_price"),
            "change_pct": item.get("change_pct"),
            "normalized_history": item.get("normalized_history", []),
            "factor_scores": item.get("factor_scores", {}),
            "signal_zone": item.get("signal_zone", "中性跟踪"),
        }
        for item in peer_candidates
    ]
    signal_rows = [
        {
            "label": "基本面",
            "score": target.get("factor_scores", {}).get("fundamental", 0),
            "comment": factor_signal_comment("基本面", target.get("factor_scores", {}).get("fundamental", 0)),
        },
        {
            "label": "趋势",
            "score": target.get("factor_scores", {}).get("trend", 0),
            "comment": factor_signal_comment("趋势", target.get("factor_scores", {}).get("trend", 0)),
        },
        {
            "label": "新闻",
            "score": target.get("factor_scores", {}).get("news", 0),
            "comment": factor_signal_comment("新闻", target.get("factor_scores", {}).get("news", 0)),
        },
        {
            "label": "宏观",
            "score": target.get("factor_scores", {}).get("macro", 0),
            "comment": factor_signal_comment("宏观", target.get("factor_scores", {}).get("macro", 0)),
        },
        {
            "label": "风控",
            "score": target.get("factor_scores", {}).get("risk", 0),
            "comment": factor_signal_comment("风控", target.get("factor_scores", {}).get("risk", 0)),
        },
    ]
    related_accounts = []
    for index, account in enumerate(target.get("accounts", []), start=1):
        account_label = account["broker"] if not share_mode else f"账户 {index}"
        demo_statement_value = share_demo_hkd(
            hkd_value(account.get("statement_value"), target["currency"]),
            f"share-detail-account-value:{target['symbol']}:{account.get('account_id') or index}",
        )
        demo_statement_pnl_pct = share_demo_pct(
            safe_pct(account.get("statement_pnl") or 0.0, (account.get("cost") or 0.0) * (account.get("quantity") or 0.0)),
            f"share-detail-account-pnl:{target['symbol']}:{account.get('account_id') or index}",
        )
        related_accounts.append(
            {
                "label": account_label,
                "account_id": account["account_id"] if not share_mode else None,
                "quantity": account.get("quantity") if not share_mode else share_demo_quantity(
                    account.get("quantity"),
                    f"share-detail-account-qty:{target['symbol']}:{account.get('account_id') or index}",
                ),
                "statement_value": hkd_value(account.get("statement_value"), target["currency"]) if not share_mode else demo_statement_value,
                "statement_pnl_pct": (
                    safe_pct(account.get("statement_pnl") or 0.0, (account.get("cost") or 0.0) * (account.get("quantity") or 0.0))
                    if not share_mode
                    else demo_statement_pnl_pct
                ),
            }
        )
    portfolio_context = [
        {
            "label": "组合定位",
            "value": holding_note["role"],
        },
        {
            "label": "仓位层级",
            "value": holding_size_bucket(target["weight_pct"]),
        },
        {
            "label": "组合权重",
            "value": f"{target['weight_pct']:.2f}%" if not share_mode else (f"{demo_weight_pct:.2f}%" if demo_weight_pct is not None else "演示中"),
        },
        {
            "label": "账户分布",
            "value": f"{target['account_count']} 个账户",
        },
        {
            "label": "浮盈亏",
            "value": (
                f"{target['statement_pnl_pct']:.2f}% / HK${target['statement_pnl_hkd']:,.0f}"
                if not share_mode
                else (
                    (
                        f"{demo_pnl_pct:+.2f}% / {'-' if (demo_pnl_hkd or 0.0) < 0 else ''}HK${abs(demo_pnl_hkd or 0.0):,.0f}"
                        if demo_pnl_pct is not None and demo_pnl_hkd is not None
                        else "演示中"
                    )
                )
            ),
        },
        {
            "label": "衍生品关联",
            "value": "存在相关衍生品或结构性敞口" if related_derivatives else "暂无相关衍生品关联",
        },
        {
            "label": "价格来源",
            "value": f"{display_price_source_label(target.get('price_source'), target.get('market_data_source'))} · {target.get('trade_date') or dashboard['analysis_date_cn']}",
        },
    ]
    latest_trade = related_trades[0] if related_trades else None
    executive_summary = [
        f"{target['name']} 当前在组合中属于“{holding_note['role']}”，仓位约 {target['weight_pct']:.2f}% ，执行建议偏向“{holding_note['stance']}”。",
        f"最新价格来自{display_price_source_label(target.get('price_source'), target.get('market_data_source'))}，交易日期 {target.get('trade_date') or dashboard['analysis_date_cn']}；当前处于 {target.get('trend_state', '无数据')} / {target.get('position_label', '无数据')}。",
        f"从商业上看，{detail['business_model']} 目前最关键的验证点是：{detail['earnings_driver']}",
        (
            f"最近新闻流 {target.get('news_signal', '中性')}，最新线索是“{target.get('news_headline')}”。"
            if target.get("news_headline")
            else f"当前新闻流 {target.get('news_signal', '中性')}，宏观环境 {target.get('macro_signal', '中性')}。"
        ),
    ]
    bull_case = [
        detail["catalyst"],
        detail["valuation_anchor"],
        f"当前综合信号 {target.get('signal_score', 50)}，若趋势继续改善，执行上更容易形成正反馈。",
    ]
    bear_case = [
        detail["red_flags"],
        detail["balance_sheet"],
        holding_note["risk"],
    ]
    action_plan = [
        holding_note["action"],
        f"最新价格来自{display_price_source_label(target.get('price_source'), target.get('market_data_source'))}，先把下一个动作建立在 {target.get('trend_state', '无数据')} 与 {'、'.join(split_watch_items(target['watch_items'])[:2])} 同步验证的前提上。",
        (
            f"最近一笔相关交易是 {latest_trade['date']} 的“{latest_trade['side']}”，下一次动作前先确认它是否与“{holding_note['stance']}”一致。"
            if latest_trade
            else "近期没有直接交易记录，下一次动作更应该先围绕验证指标与风险预算，而不是成本线。"
        ),
    ]
    watchlist = split_watch_items(target["watch_items"])
    relevant_macro_topics = [
        item
        for item in dashboard.get("macro", {}).get("topics", [])
        if target["category"] in item.get("impact_categories", [])
    ]
    if not relevant_macro_topics:
        relevant_macro_topics = (dashboard.get("macro", {}).get("topics") or [])[:2]
    detail_ai = build_default_stock_detail_ai(
        target,
        detail,
        holding_note,
        executive_summary,
        bull_case,
        bear_case,
        watchlist,
        action_plan,
        latest_trade,
    )
    detail_ai_payload = {
        "summary": {
            "symbol": target["symbol"],
            "name": target["name"],
            "category_name": target["category_name"],
            "style_label": target["style_label"],
            "portfolio_role": holding_note["role"],
            "stance": holding_note["stance"],
            "weight_pct": None if share_mode else round(target["weight_pct"], 2),
            "signal_score": target.get("signal_score"),
            "signal_zone": target.get("signal_zone"),
            "trend_state": target.get("trend_state"),
            "position_label": target.get("position_label"),
            "macro_signal": target.get("macro_signal"),
            "news_signal": target.get("news_signal"),
            "price_source": display_price_source_label(target.get("price_source"), target.get("market_data_source")),
            "trade_date": target.get("trade_date") or dashboard["analysis_date_cn"],
            "related_trade_count": len(related_trades),
            "related_derivative_count": len(related_derivatives),
            "peer_count": len(peer_candidates),
        },
        "fundamentals": {
            key: value
            for key, value in detail.items()
            if key in {"business_model", "earnings_driver", "valuation_anchor", "catalyst", "balance_sheet", "red_flags"}
        },
        "rule_based": {
            "executive_summary": executive_summary[:4],
            "bull_case": bull_case[:3],
            "bear_case": bear_case[:3],
            "watchlist": watchlist[:6],
            "action_plan": action_plan[:3],
            "holding_note": {
                "role": holding_note["role"],
                "stance": holding_note["stance"],
                "risk": holding_note["risk"],
                "action": holding_note["action"],
            },
        },
        "news": {
            "signal": target.get("news_signal"),
            "headline": target.get("news_headline"),
        },
        "macro_topics": [
            {
                "name": item.get("name"),
                "severity": item.get("severity"),
                "headline": item.get("headline"),
                "summary": item.get("summary"),
            }
            for item in relevant_macro_topics[:3]
        ],
        "peers": [
            {
                "symbol": item["symbol"],
                "name": item["name"],
                "signal_score": item.get("signal_score"),
                "signal_zone": item.get("signal_zone"),
                "trend_state": item.get("trend_state"),
                "change_pct": item.get("change_pct"),
            }
            for item in peer_candidates[:3]
        ],
        "recent_trades": [
            {
                "date": item["date"],
                "side": item["side"],
                "broker": item["broker"] if not share_mode else "已脱敏账户",
                "price": item["price"] if not share_mode else None,
                "currency": item["currency"],
            }
            for item in related_trades[:4]
        ],
        "related_derivatives": [
            {
                "symbol": item["symbol"],
                "description": item["description"] if not share_mode else "存在相关衍生品或结构性敞口",
                "estimated_notional_hkd": item["estimated_notional_hkd"] if not share_mode else None,
            }
            for item in related_derivatives[:3]
        ],
    }
    if not include_live:
        detail_ai = enhance_stock_detail_ai(detail_ai, detail_ai_payload, ai_request_config=ai_request_config)
    if share_mode:
        detail_ai = sanitize_stock_detail_ai_for_share(detail_ai)
    price_cards = [
        {
            "label": "当前价格",
            "value": f"{'HK$' if target['currency'] == 'HKD' else '$'}{(target.get('current_price') or 0):,.2f}" if target.get("current_price") is not None else "--",
            "delta": f"{target.get('change_pct', 0):+.2f}%" if target.get("change_pct") is not None else "--",
        },
        {
            "label": "行情日期",
            "value": target.get("trade_date") or dashboard["analysis_date_cn"] or "--",
            "delta": display_price_source_label(target.get("price_source"), target.get("market_data_source")),
        },
        {
            "label": "持仓成本",
            "value": (
                f"{'HK$' if target['currency'] == 'HKD' else '$'}{(target.get('avg_cost') or 0):,.2f}"
                if not share_mode and target.get("avg_cost") is not None
                else (
                    f"{'HK$' if target['currency'] == 'HKD' else '$'}{demo_avg_cost:,.2f}"
                    if share_mode and demo_avg_cost is not None
                    else "--"
                )
            ),
            "delta": "平均成本",
        },
        {
            "label": "60日位置",
            "value": target.get("position_label") or "无数据",
            "delta": target.get("trend_state") or "无数据",
        },
    ]
    focus_cards = [
        {
            "label": "行情状态",
            "value": target.get("trade_date") or dashboard["analysis_date_cn"] or "--",
            "detail": f"{display_price_source_label(target.get('price_source'), target.get('market_data_source'))} · 详情页已单独刷新当前标的",
        },
        {
            "label": "新闻流",
            "value": target.get("news_signal", "中性"),
            "detail": target.get("news_headline") or "暂无新的个股新闻摘要，当前以本地研究快照为主。",
        },
        {
            "label": "执行锚点",
            "value": holding_note["stance"],
            "detail": holding_note["action"],
        },
        {
            "label": "最近交易提示",
            "value": f"{len(related_trades)} 笔相关交易" if related_trades else "暂无直接交易",
            "detail": (
                f"{latest_trade['date']} 最近一次是“{latest_trade['side']}”，需要和当前持仓定位一起看。"
                if latest_trade
                else "没有近期直接交易，适合把下一次动作完全建立在验证指标和趋势上。"
            ),
        },
    ]
    return {
        "generated_at": dashboard["generated_at"],
        "analysis_date_cn": dashboard["analysis_date_cn"],
        "share_mode": share_mode,
        "hero": {
            "symbol": target["symbol"],
            "name": target["name"],
            "category_name": target["category_name"],
            "style_label": target["style_label"],
            "fundamental_label": target["fundamental_label"],
            "signal_score": target.get("signal_score", 50),
            "signal_zone": target.get("signal_zone", "中性跟踪"),
            "trend_state": target.get("trend_state", "无数据"),
            "position_label": target.get("position_label", "无数据"),
            "macro_signal": target.get("macro_signal", "中性"),
            "news_signal": target.get("news_signal", "中性"),
            "current_price": target.get("current_price"),
            "change_pct": target.get("change_pct"),
            "change_pct_5d": target.get("change_pct_5d"),
            "trade_date": target.get("trade_date"),
            "price_source": target.get("price_source"),
            "price_source_label": display_price_source_label(target.get("price_source"), target.get("market_data_source")),
            "news_headline": target.get("news_headline"),
        },
        "source_meta": {
            "price_source_label": display_price_source_label(target.get("price_source"), target.get("market_data_source")),
            "live_updated_at": detail_live_bundle.get("updated_at") or dashboard.get("live", {}).get("updated_at"),
            "macro_updated_at": dashboard.get("macro", {}).get("updated_at"),
            "trade_date": target.get("trade_date") or dashboard["analysis_date_cn"],
        },
        "ai_detail": detail_ai,
        "executive_summary": detail_ai["executive_summary"],
        "focus_cards": focus_cards,
        "signal_rows": signal_rows,
        "signal_matrix": build_detail_signal_matrix(target, peer_candidates),
        "portfolio_context": portfolio_context,
        "price_cards": price_cards,
        "account_rows": related_accounts,
        "related_trades": [
            {
                "date": item["date"],
                "side": item["side"],
                "broker": item["broker"] if not share_mode else account_alias_by_id.get(item.get("account_id"), "账户"),
                "quantity": item["quantity"] if not share_mode else share_demo_quantity(
                    item.get("quantity"),
                    f"share-detail-trade-qty:{target['symbol']}:{item.get('account_id')}:{item['date']}:{item['side']}",
                ),
                "price": item["price"] if not share_mode else share_demo_price(
                    item.get("price"),
                    f"share-detail-trade-price:{target['symbol']}:{item.get('account_id')}:{item['date']}:{item['side']}",
                ),
                "currency": item["currency"],
            }
            for item in related_trades
        ],
        "derivative_rows": [
            {
                "symbol": item["symbol"],
                "description": (
                    item["description"]
                    if not share_mode
                    else ("相关期权或结构性产品敞口" if item.get("underlyings") else "相关衍生品或结构性产品敞口")
                ),
                "estimated_notional_hkd": item["estimated_notional_hkd"] if not share_mode else share_demo_hkd(
                    item.get("estimated_notional_hkd"),
                    f"share-detail-derivative:{target['symbol']}:{item.get('account_id')}:{item['symbol']}",
                    minimum_non_zero=1800.0,
                ),
            }
            for item in related_derivatives
        ],
        "bull_case": detail_ai["bull_case"],
        "bear_case": detail_ai["bear_case"],
        "watchlist": detail_ai["watchlist"],
        "action_plan": detail_ai["action_plan"],
        "peers": peers,
        "history": target.get("history", []),
        "comparison_history": build_detail_comparison_history(target, peer_candidates),
        "holding_note": holding_note,
    }


def demoize_weight_rows(rows: list[dict[str, Any]], seed_prefix: str) -> list[dict[str, Any]]:
    if not rows:
        return []
    raw_values = []
    for index, row in enumerate(rows):
        actual_weight = float(row.get("weight_pct") or 0.0)
        seed = f"{seed_prefix}:{row.get('id') or row.get('label') or row.get('symbol') or index}"
        raw = max(2.8, actual_weight * 0.62 + (len(rows) - index) * 1.2 + stable_unit(seed) * 3.4)
        raw_values.append(raw)
    total = sum(raw_values) or 1.0
    demo_rows = []
    for row, raw in zip(rows, raw_values):
        demo_rows.append({**row, "weight_pct": round(raw / total * 100.0, 2), "is_virtual": True})
    return demo_rows


def demoize_top_holdings(holdings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    demo_weights = demoize_weight_rows(
        [{"symbol": item["symbol"], "weight_pct": item["weight_pct"]} for item in holdings[:12]],
        "share-holding-weight",
    )
    weight_by_symbol = {item["symbol"]: item["weight_pct"] for item in demo_weights}
    rows = []
    for item in holdings[:12]:
        unit = stable_unit(f"share-pnl:{item['symbol']}")
        base_pnl = float(item.get("statement_pnl_pct") or 0.0)
        demo_pnl_pct = round(max(-26.0, min(24.0, base_pnl * 0.35 + (unit - 0.5) * 13.0)), 2)
        rows.append(
            {
                "symbol": item["symbol"],
                "name": item["name"],
                "category_name": item["category_name"],
                "style_label": item["style_label"],
                "fundamental_label": item["fundamental_label"],
                "signal_score": item.get("signal_score", 50),
                "signal_zone": item.get("signal_zone", "中性跟踪"),
                "trend_state": item.get("trend_state", "无数据"),
                "macro_signal": item.get("macro_signal", "中性"),
                "news_signal": item.get("news_signal", "中性"),
                "current_price": item.get("current_price"),
                "change_pct": item.get("change_pct"),
                "change_pct_5d": item.get("change_pct_5d"),
                "currency": item["currency"],
                "market_source_label": item.get("market_source_label"),
                "trade_date": item.get("trade_date"),
                "demo_weight_pct": weight_by_symbol.get(item["symbol"], 0.0),
                "demo_pnl_pct": demo_pnl_pct,
                "demo_size_index": round(55 + weight_by_symbol.get(item["symbol"], 0.0) * 1.8 + stable_unit(f"share-size:{item['symbol']}") * 18, 1),
            }
        )
    return rows


def sanitize_share_text(text: str | None) -> str:
    if not text:
        return ""
    sanitized = str(text)
    sanitized = re.sub(r"\d+(?:\.\d+)?\s*(?:亿|万)\s*(?:HKD|USD|港元|港币|美元)?", "演示规模", sanitized)
    sanitized = re.sub(r"(?:HKD|USD)\s?[\d,]+(?:\.\d+)?", "演示规模", sanitized)
    sanitized = re.sub(r"HK\$\s?[\d,]+(?:\.\d+)?", "演示规模", sanitized)
    sanitized = re.sub(r"(?<![A-Z])\$\s?[\d,]+(?:\.\d+)?", "演示规模", sanitized)
    sanitized = re.sub(r"[+-]?\d+(?:\.\d+)?%", "演示比例", sanitized)
    return sanitized


def sanitize_ai_insights_for_share(ai_insights: dict[str, Any]) -> dict[str, Any]:
    return {
        **ai_insights,
        "headline": sanitize_share_text(ai_insights.get("headline")),
        "deep_summary": sanitize_share_text(ai_insights.get("deep_summary")),
        "cards": [
            {
                **card,
                "title": sanitize_share_text(card.get("title")),
                "detail": sanitize_share_text(card.get("detail")),
            }
            for card in ai_insights.get("cards", [])
        ],
        "playbook": [sanitize_share_text(item) for item in ai_insights.get("playbook", [])],
        "sections": [
            {
                "title": sanitize_share_text(item.get("title")),
                "summary": sanitize_share_text(item.get("summary")),
                "bullets": [sanitize_share_text(point) for point in item.get("bullets", [])],
            }
            for item in ai_insights.get("sections", [])
        ],
        "position_actions": [
            {
                "symbol": sanitize_share_text(item.get("symbol")),
                "name": sanitize_share_text(item.get("name")),
                "stance": sanitize_share_text(item.get("stance")),
                "thesis": sanitize_share_text(item.get("thesis")),
                "trigger": sanitize_share_text(item.get("trigger")),
                "risk": sanitize_share_text(item.get("risk")),
                "action": sanitize_share_text(item.get("action")),
            }
            for item in ai_insights.get("position_actions", [])
        ],
    }


def sanitize_stock_detail_ai_for_share(ai_detail: dict[str, Any]) -> dict[str, Any]:
    return {
        **ai_detail,
        "headline": sanitize_share_text(ai_detail.get("headline")),
        "deep_summary": sanitize_share_text(ai_detail.get("deep_summary")),
        "executive_summary": [sanitize_share_text(item) for item in ai_detail.get("executive_summary", [])],
        "sections": [
            {
                "title": sanitize_share_text(item.get("title")),
                "summary": sanitize_share_text(item.get("summary")),
                "bullets": [sanitize_share_text(point) for point in item.get("bullets", [])],
            }
            for item in ai_detail.get("sections", [])
        ],
        "bull_case": [sanitize_share_text(item) for item in ai_detail.get("bull_case", [])],
        "bear_case": [sanitize_share_text(item) for item in ai_detail.get("bear_case", [])],
        "watchlist": [sanitize_share_text(item) for item in ai_detail.get("watchlist", [])],
        "action_plan": [sanitize_share_text(item) for item in ai_detail.get("action_plan", [])],
    }


def build_share_demo_charts(payload: dict[str, Any]) -> dict[str, Any]:
    holdings = payload["holdings"]
    top_demo_holdings = demoize_top_holdings(holdings)
    demo_weight_by_symbol = {item["symbol"]: item["demo_weight_pct"] for item in top_demo_holdings}
    demo_pnl_by_symbol = {item["symbol"]: item["demo_pnl_pct"] for item in top_demo_holdings}

    style_rows = []
    for row in payload["charts"]["style_mix"]:
        members = row.get("core_holdings") or []
        member_symbols = [item["symbol"] for item in holdings if item["name"] in members]
        demo_avg_pnl = 0.0
        if member_symbols:
            demo_avg_pnl = sum(demo_pnl_by_symbol.get(symbol, 0.0) for symbol in member_symbols) / len(member_symbols)
        style_rows.append({**row, "avg_pnl_pct": round(demo_avg_pnl, 2)})

    regime_rows = []
    for row in payload["charts"]["price_regime"]:
        regime_rows.append({**row, "avg_signal": round(float(row.get("avg_signal") or 0.0), 2)})

    scatter_rows = []
    for item in top_demo_holdings:
        scatter_rows.append(
            {
                "symbol": item["symbol"],
                "name": item["name"],
                "market": "SHARE",
                "x": item["demo_weight_pct"],
                "y": item["demo_pnl_pct"],
                "size": item["demo_size_index"] ** 2,
                "size_index": item["demo_size_index"],
                "category_name": item["category_name"],
                "macro_signal": item["macro_signal"],
                "is_virtual": True,
            }
        )

    return {
        "theme_donut": demoize_weight_rows(payload["charts"]["theme_donut"], "share-theme"),
        "style_mix": demoize_weight_rows(style_rows, "share-style"),
        "price_regime": demoize_weight_rows(regime_rows, "share-regime"),
        "holding_scatter": scatter_rows,
        "top_holdings": top_demo_holdings,
    }


def build_share_dimension_rows(
    rows: list[dict[str, Any]],
    seed_prefix: str,
    total_demo_value_hkd: float,
) -> list[dict[str, Any]]:
    demo_rows = demoize_weight_rows(rows, seed_prefix)
    return [
        {
            **row,
            "demo_value_hkd": round(total_demo_value_hkd * float(row.get("weight_pct") or 0.0) / 100.0, 2),
        }
        for row in demo_rows
    ]


def build_share_accounts(payload: dict[str, Any], total_demo_nav_hkd: float) -> tuple[list[dict[str, Any]], dict[str, str]]:
    account_cards = payload.get("accounts", [])
    demo_nav_rows = build_share_dimension_rows(
        [{"id": card["account_id"], "weight_pct": card["nav_hkd"]} for card in account_cards],
        "share-account-nav",
        total_demo_nav_hkd,
    )
    nav_by_account_id = {item["id"]: item["demo_value_hkd"] for item in demo_nav_rows}
    derivative_by_account: dict[str, float] = defaultdict(float)
    for item in payload.get("derivatives", []):
        derivative_by_account[item["account_id"]] += float(item.get("estimated_notional_hkd") or 0.0)
    account_alias_by_id = {card["account_id"]: f"账户 {index}" for index, card in enumerate(account_cards, start=1)}
    rows = []
    for index, card in enumerate(account_cards, start=1):
        account_seed = f"share-account:{card['account_id']}"
        rows.append(
            {
                "label": account_alias_by_id.get(card["account_id"], f"账户 {index}"),
                "broker": card["broker"],
                "statement_date": card["statement_date"],
                "holding_count": card["holding_count"],
                "trade_count": card["trade_count"],
                "derivative_count": card["derivative_count"],
                "risk_notes": [sanitize_share_text(note) for note in card.get("risk_notes", [])],
                "top_names": card.get("top_names"),
                "demo_nav_hkd": nav_by_account_id.get(card["account_id"], share_demo_hkd(card.get("nav_hkd"), f"{account_seed}:nav")),
                "demo_financing_hkd": share_demo_hkd(card.get("financing_hkd"), f"{account_seed}:financing", minimum_non_zero=800.0),
                "demo_derivative_hkd": share_demo_hkd(
                    derivative_by_account.get(card["account_id"]),
                    f"{account_seed}:derivative",
                    minimum_non_zero=1200.0,
                ),
                "demo_weight_pct": next(
                    (
                        float(item.get("weight_pct") or 0.0)
                        for item in demo_nav_rows
                        if item.get("id") == card["account_id"]
                    ),
                    0.0,
                ),
            }
        )
    return rows, account_alias_by_id


def build_share_derivatives(derivatives: list[dict[str, Any]], account_alias_by_id: dict[str, str]) -> list[dict[str, Any]]:
    rows = []
    for index, item in enumerate(derivatives[:8], start=1):
        underlyings = item.get("underlyings") or []
        if underlyings:
            description = f"关联 {' / '.join(underlyings[:2])} 的期权或结构性敞口"
        else:
            description = "相关衍生品或结构性产品敞口"
        rows.append(
            {
                "symbol": item["symbol"],
                "account_label": account_alias_by_id.get(item.get("account_id"), f"账户 {index}"),
                "description": description,
                "demo_notional_hkd": share_demo_hkd(
                    item.get("estimated_notional_hkd"),
                    f"share-derivative:{item.get('account_id')}:{item['symbol']}",
                    minimum_non_zero=1800.0,
                ),
            }
        )
    return rows


def build_share_payload(
    force_refresh: bool = False,
    include_live: bool = True,
    allow_cached_fallback: bool = True,
) -> dict[str, Any]:
    payload = build_dashboard_payload(
        force_refresh=force_refresh,
        include_live=include_live,
        allow_cached_fallback=allow_cached_fallback,
    )
    top_theme_names = [item["label"] for item in payload["breakdowns"]["themes"][:3]]
    share_demo = build_share_demo_charts(payload)
    share_ai_insights = sanitize_ai_insights_for_share(payload["ai_insights"])
    share_strategy_views = [
        {
            **item,
            "tag": sanitize_share_text(item.get("tag")),
            "summary": sanitize_share_text(item.get("summary")),
        }
        for item in payload["strategy_views"]
    ]
    share_macro_topics = []
    for item in payload["macro"]["topics"]:
        share_macro_topics.append(
            {
                **item,
                "headline": sanitize_share_text(item.get("headline")),
                "summary": sanitize_share_text(item.get("summary")),
                "impact_weight_pct": round(
                    max(6.0, float(item.get("impact_weight_pct") or 0.0) * 0.58 + stable_unit(f"share-macro:{item.get('id') or item.get('name')}") * 6.0),
                    2,
                ),
            }
        )
    notes_by_symbol = {item["symbol"]: item for item in payload["brief"]["holding_notes"]}
    demo_holding_by_symbol = {item["symbol"]: item for item in share_demo["top_holdings"]}
    public_holdings = []
    public_brief = []
    for item in payload["holdings"][:12]:
        note = notes_by_symbol.get(item["symbol"], {})
        demo = demo_holding_by_symbol.get(item["symbol"], {})
        public_holdings.append(
            {
                "symbol": item["symbol"],
                "name": item["name"],
                "category_name": item["category_name"],
                "style_label": item["style_label"],
                "fundamental_label": item["fundamental_label"],
                "signal_score": item.get("signal_score", 50),
                "signal_zone": item.get("signal_zone", "中性跟踪"),
                "trend_state": item.get("trend_state", "无数据"),
                "macro_signal": item.get("macro_signal", "中性"),
                "news_signal": item.get("news_signal", "中性"),
                "current_price": item.get("current_price"),
                "change_pct": item.get("change_pct"),
                "change_pct_5d": item.get("change_pct_5d"),
                "currency": item["currency"],
                "market_source_label": item.get("market_source_label"),
                "trade_date": item.get("trade_date"),
                "stance": note.get("stance") or "继续跟踪",
                "summary": sanitize_share_text(note.get("thesis") or item["business_note"]),
                "action": sanitize_share_text(note.get("action") or "维持跟踪并等待验证。"),
                "demo_weight_pct": demo.get("demo_weight_pct"),
                "demo_pnl_pct": demo.get("demo_pnl_pct"),
                "demo_size_index": demo.get("demo_size_index"),
            }
        )
        public_brief.append(
            {
                "symbol": item["symbol"],
                "name": item["name"],
                "category_name": item["category_name"],
                "role": note.get("role") or item["style_label"],
                "stance": note.get("stance") or "继续跟踪",
                "thesis": sanitize_share_text(note.get("thesis") or item["business_note"]),
                "watch_items": sanitize_share_text(note.get("watch_items") or item["watch_items"]),
                "risk": sanitize_share_text(note.get("risk") or item["fundamental_note"]),
                "action": sanitize_share_text(note.get("action") or "维持跟踪并等待验证。"),
                "trend_state": item.get("trend_state", "无数据"),
                "signal_zone": item.get("signal_zone", "中性跟踪"),
                "demo_weight_pct": demo.get("demo_weight_pct"),
                "demo_pnl_pct": demo.get("demo_pnl_pct"),
                "current_price": item.get("current_price"),
                "change_pct": item.get("change_pct"),
                "currency": item["currency"],
                "market_source_label": item.get("market_source_label"),
            }
        )
    ai_engine = payload["ai_insights"].get("engine") or fallback_ai_engine_meta()
    live = payload.get("live", {})
    provider_counts = live.get("provider_counts", {})
    provider_summary = provider_summary_text(provider_counts) or "无在线行情"
    demo_total_nav_hkd = share_demo_hkd(payload["summary"].get("total_nav_hkd"), "share-summary-nav", minimum_non_zero=30000.0) or 0.0
    demo_total_statement_value_hkd = share_demo_hkd(
        payload["summary"].get("total_statement_value_hkd"),
        "share-summary-equity",
        minimum_non_zero=22000.0,
    ) or 0.0
    demo_total_financing_hkd = share_demo_hkd(
        payload["summary"].get("total_financing_hkd"),
        "share-summary-financing",
        minimum_non_zero=2600.0,
    ) or 0.0
    demo_total_derivative_notional_hkd = share_demo_hkd(
        payload["summary"].get("total_derivative_notional_hkd"),
        "share-summary-derivative",
        minimum_non_zero=3200.0,
    ) or 0.0
    share_accounts, account_alias_by_id = build_share_accounts(payload, demo_total_nav_hkd)
    share_breakdowns = {
        "themes": build_share_dimension_rows(payload["breakdowns"]["themes"], "share-breakdown-theme", demo_total_statement_value_hkd),
        "markets": build_share_dimension_rows(payload["breakdowns"]["markets"], "share-breakdown-market", demo_total_statement_value_hkd),
        "brokers": build_share_dimension_rows(payload["breakdowns"]["brokers"], "share-breakdown-broker", demo_total_nav_hkd),
    }
    share_derivatives = build_share_derivatives(payload["derivatives"], account_alias_by_id)
    public_trades = [
        {
            "date": item["date"],
            "symbol": item["symbol"],
            "side": item["side"],
            "broker": account_alias_by_id.get(item.get("account_id"), "账户"),
        }
        for item in payload["trades"][:10]
    ]
    return {
        "generated_at": payload["generated_at"],
        "analysis_date_cn": payload["analysis_date_cn"],
        "headline": (
            f"脱敏演示版保留了 {payload['summary']['account_count']} 个账户、"
            f"{payload['summary']['holding_count']} 个持仓的模块结构，资金与仓位全部替换为 mock 数据。"
        ),
        "overview": (
            f"当前以 {'、'.join(top_theme_names)} 为主线，保留资产总览、账户视角、市场/主题/风格拆分、近期交易与衍生品等模块。"
            "所有资金规模、仓位、市值、收益和账户层字段均已替换为比真实组合低一个量级以上的演示数据；"
            "当前价、涨跌幅、趋势状态、宏观主题和执行建议仍来自公开行情或研究框架。"
        ),
        "share_notice": "该分享版现在保留个人资产总览、账户视角、市场/主题/风格、交易与衍生品等模块，但所有资金规模均为演示值，不代表真实净值或仓位。",
        "demo_notice": "演示字段包括：演示净资产、演示市值、演示融资、演示衍生品名义本金、演示权重、演示收益和演示热度指数。整体规模已缩小到真实组合的一成以下。",
        "demo_summary": {
            "account_count": payload["summary"]["account_count"],
            "holding_count": payload["summary"]["holding_count"],
            "trade_count": payload["summary"]["trade_count"],
            "derivative_count": payload["summary"]["derivative_count"],
            "total_nav_hkd": demo_total_nav_hkd,
            "total_statement_value_hkd": demo_total_statement_value_hkd,
            "total_financing_hkd": demo_total_financing_hkd,
            "total_derivative_notional_hkd": demo_total_derivative_notional_hkd,
        },
        "share_meta": {
            "ai_label": ai_engine.get("label"),
            "ai_note": sanitize_share_text(ai_engine.get("note")),
            "market_summary": provider_summary,
            "trade_window_days": HISTORY_POINTS,
        },
        "ai_insights": share_ai_insights,
        "strategy_views": share_strategy_views,
        "demo_charts": share_demo,
        "breakdowns": share_breakdowns,
        "macro": {
            **payload["macro"],
            "topics": share_macro_topics,
        },
        "accounts": share_accounts,
        "holdings": public_holdings,
        "top_holdings": public_holdings,
        "recent_trades": public_trades,
        "derivatives": share_derivatives,
        "brief": {
            "priority_actions": [
                {
                    **item,
                    "title": sanitize_share_text(item.get("title")),
                    "detail": sanitize_share_text(item.get("detail")),
                }
                for item in payload["brief"]["priority_actions"]
            ],
            "holding_notes": public_brief,
        },
        "live": live,
    }


def monitored_statements(accounts: list[dict[str, Any]], user_id: str | None = None) -> list[dict[str, Any]]:
    date_by_account = {account["account_id"]: account["statement_date"] for account in accounts}
    source_states = {}
    for account in accounts:
        account_id = account.get("account_id")
        if account_id:
            source_states[account_id] = {
                "statement_date": account.get("statement_date"),
                "load_status": account.get("load_status"),
                "issue": account.get("load_issue"),
            }
    rows = []
    for item in get_statement_sources(user_id=user_id):
        path = Path(item["path"])
        status = source_states.get(item["account_id"], {})
        rows.append(
            {
                "broker": item["broker"],
                "account_id": item["account_id"],
                "statement_type": item["type"],
                "statement_date": status.get("statement_date") or date_by_account.get(item["account_id"]),
                "file_name": path.name,
                "source_mode": item.get("source_mode", "default"),
                "uploaded_at": item.get("uploaded_at"),
                "file_exists": path.exists(),
                "load_status": status.get("load_status") or ("parsed" if path.exists() else "error"),
                "issue": status.get("issue"),
            }
        )
    return rows


def _empty_dashboard_payload(user_id: str | None = None) -> dict[str, Any]:
    today = now_cn_date()
    headline = "先登录并导入你的第一份券商数据"
    overview = "当前账号下还没有持仓、交易或结单数据。你可以继续上传结单，或在设置页查看各券商的接入条件。"
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "analysis_date_cn": today,
        "snapshot_date": today,
        "summary": {
            "account_count": 0,
            "holding_count": 0,
            "trade_count": 0,
            "derivative_count": 0,
            "total_nav_hkd": 0.0,
            "total_statement_value_hkd": 0.0,
            "total_financing_hkd": 0.0,
            "total_derivative_notional_hkd": 0.0,
            "top5_ratio": 0.0,
            "top1_weight_pct": 0.0,
            "statement_start_date": today,
            "statement_end_date": today,
        },
        "headline": headline,
        "overview": overview,
        "live": {
            "updated_at": None,
            "tracked_count": 0,
            "errors": [],
            "source_mode": "empty",
            "fallback_symbols": [],
            "provider_counts": {},
            "provider_summary": "",
        },
        "macro": {
            "updated_at": None,
            "topics": [],
            "errors": [],
            "source_mode": "empty",
        },
        "source_health": {
            "parsed_count": 0,
            "cached_count": 0,
            "error_count": 0,
        },
        "methodology": {
            "ai_engine": fallback_ai_engine_meta(),
            "market_data": {
                "history_window_days": HISTORY_POINTS,
                "provider_counts": {},
                "provider_summary": "",
                "fallback_rule": "尚未导入数据，暂不启动在线行情与缓存回退链路。",
            },
        },
        "ai_insights": empty_ai_insights(),
        "key_drivers": [],
        "risk_flags": [],
        "accounts": [],
        "breakdowns": {
            "themes": [],
            "markets": [],
            "brokers": [],
        },
        "charts": {
            "theme_donut": [],
            "broker_risk": [],
            "holding_scatter": [],
            "performance": [],
            "health_radar": [],
            "style_mix": [],
            "signal_heatmap": [],
            "price_regime": [],
            "macro_topics": [],
        },
        "holdings": [],
        "top_holdings": [],
        "fundamental_deep_dive": [],
        "trades": [],
        "derivatives": [],
        "strategy_views": [],
        "brief": {
            "headline": headline,
            "overview": overview,
            "priority_actions": [
                {
                    "title": "先完成首个用户数据导入",
                    "detail": "用手机号或微信完成登录后，优先上传券商结单，或在设置页查看券商自动同步的官方接入要求。",
                }
            ],
            "framework": REFERENCE_FRAMEWORK,
            "holding_notes": [],
            "disclaimer": "当前页面还没有用户级投资数据，暂不生成组合判断。",
        },
        "update_guide": [
            "首次使用先登录，再上传第一份结单建立你的账户数据。",
            "如果暂时没有自动同步能力，可以先通过 PDF 结单完成持仓和交易导入。",
            "设置页会标出各家券商当前的接入方式和准备事项。",
        ],
        "statement_sources": monitored_statements([], user_id=user_id),
        "reference_sources": [
            {
                "label": item["label"],
                "type": item["type"],
                "file_name": Path(item["path"]).name,
            }
            for item in get_reference_analysis_sources(user_id=user_id)
        ],
    }


def build_dashboard_payload(
    force_refresh: bool = False,
    include_live: bool = True,
    allow_cached_fallback: bool = True,
    strict_account_ids: set[str] | None = None,
    include_ai: bool = True,
    user_id: str | None = None,
    refresh_portfolio: bool = False,
    ai_request_config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    portfolio = load_real_portfolio(
        force_refresh=force_refresh and refresh_portfolio,
        allow_cached_fallback=allow_cached_fallback,
        strict_account_ids=strict_account_ids,
        user_id=user_id,
    )
    research_cache = load_local_analysis_cache()
    accounts = portfolio["accounts"]
    if not accounts:
        return _empty_dashboard_payload(user_id=user_id)
    total_value_hkd = portfolio["total_statement_value_hkd"]
    holdings = [normalize_holding(item, total_value_hkd) for item in portfolio["aggregate_holdings"]]
    holdings.sort(key=lambda item: item["statement_value_hkd"], reverse=True)
    account_cards = build_account_cards(accounts)
    derivatives = [normalize_derivative(item) for item in portfolio["derivatives"]]
    trades = [normalize_trade(item) for item in portfolio["recent_trades"]]
    total_derivative_notional_hkd = round(sum(item["estimated_notional_hkd"] for item in derivatives), 2)
    live_bundle = {
        "updated_at": None,
        "rows_by_symbol": {},
        "errors": [],
        "source_mode": "empty",
        "fallback_symbols": [],
        "provider_counts": {},
    }
    macro_bundle = {"updated_at": None, "topics": [], "category_scores": {}, "errors": [], "source_mode": "empty"}
    if include_live:
        with ThreadPoolExecutor(max_workers=2) as executor:
            live_future = executor.submit(fetch_live_bundle, holdings, force_refresh, True)
            macro_future = executor.submit(fetch_macro_bundle, force_refresh, True)
            live_bundle = live_future.result()
            macro_bundle = macro_future.result()
    else:
        live_bundle = fetch_live_bundle(holdings, force_refresh=force_refresh, allow_network=False)
        macro_bundle = fetch_macro_bundle(force_refresh=force_refresh, allow_network=False)
    holdings = enrich_holdings_with_live_and_macro(
        holdings,
        live_bundle.get("rows_by_symbol", {}),
        macro_bundle.get("category_scores", {}),
        research_cache,
    )
    risk_flags = build_risk_flags(
        holdings,
        portfolio["total_nav_hkd"],
        portfolio["total_financing_hkd"],
        total_derivative_notional_hkd,
        portfolio["top5_ratio"],
    )

    snapshot_dates = sorted(account["statement_date"] for account in accounts)
    theme_breakdown = build_theme_breakdown(holdings)
    market_breakdown = build_breakdown(holdings, "market", "market")
    broker_breakdown = build_broker_breakdown(account_cards)
    holding_notes = [diagnose_holding(item) for item in holdings]
    fundamental_deep_dive = build_fundamental_deep_dive(holdings)
    macro_topics = build_macro_flash_topics(macro_bundle, holdings)
    strategy_views = build_strategy_views(
        holdings,
        macro_bundle,
        portfolio["total_financing_hkd"],
        total_derivative_notional_hkd,
        portfolio["total_nav_hkd"],
    )
    key_drivers = build_key_drivers(holdings, risk_flags, macro_topics)
    ai_insights = (
        build_ai_insights(
            holdings,
            trades,
            derivatives,
            portfolio["total_nav_hkd"],
            portfolio["total_financing_hkd"],
            total_derivative_notional_hkd,
            macro_topics,
            ai_request_config=ai_request_config,
        )
        if include_ai
        else empty_ai_insights()
    )
    source_health = portfolio.get("source_health") or {"parsed_count": len(accounts), "cached_count": 0, "error_count": 0}

    main_theme_names = "、".join(item["label"] for item in theme_breakdown[:3])
    top_names = "、".join(item["name"] for item in holdings[:5])
    live_mode_map = {
        "network": "在线行情",
        "mixed": "在线行情 + 最近同步价格",
        "cache": "最近同步价格",
        "empty": "结单价格",
    }
    macro_mode_map = {
        "network": "在线宏观新闻",
        "mixed": "在线宏观新闻 + 参考研究",
        "cache": "参考研究",
        "empty": "静态框架",
    }
    provider_counts = live_bundle.get("provider_counts", {})
    provider_summary = provider_summary_text(provider_counts)
    source_cache_overview = ""
    if source_health.get("cached_count"):
        source_cache_overview = f"结单层有 {source_health['cached_count']} 个账户使用缓存快照。"
    headline = (
        f"截至 {snapshot_dates[-1]} 的真实结单快照显示，这是一组以 {main_theme_names} 为主轴、"
        f"头部仓位集中在 {top_names} 的高波动组合。"
    )
    overview = (
        f"股票市值约 HK${portfolio['total_statement_value_hkd']:,.0f}，净资产约 HK${portfolio['total_nav_hkd']:,.0f}，"
        f"融资相关负现金约 HK${portfolio['total_financing_hkd']:,.0f}。"
        f"当前价格层使用 {live_mode_map.get(live_bundle.get('source_mode'), '离线快照')}，"
        f"{f'主数据源为 {provider_summary}；' if provider_summary else ''}"
        f"60 日走势窗口固定为 {HISTORY_POINTS} 个交易日，接口异常时自动回退到本地日更快照，再兜底到结单价格。"
        f"宏观层使用 {macro_mode_map.get(macro_bundle.get('source_mode'), '静态框架')}。"
        f"{source_cache_overview}"
        "建议阅读顺序是：先看关键驱动与风险旗标，再看优先动作，最后逐只检查个股定位。"
    )

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "analysis_date_cn": now_cn_date(),
        "snapshot_date": snapshot_dates[-1],
        "summary": {
            "account_count": len(accounts),
            "holding_count": len(holdings),
            "trade_count": len(trades),
            "derivative_count": len(derivatives),
            "total_nav_hkd": portfolio["total_nav_hkd"],
            "total_statement_value_hkd": portfolio["total_statement_value_hkd"],
            "total_financing_hkd": portfolio["total_financing_hkd"],
            "total_derivative_notional_hkd": total_derivative_notional_hkd,
            "top5_ratio": portfolio["top5_ratio"],
            "top1_weight_pct": holdings[0]["weight_pct"] if holdings else 0.0,
            "statement_start_date": snapshot_dates[0],
            "statement_end_date": snapshot_dates[-1],
        },
        "headline": headline,
        "overview": overview,
        "live": {
            "updated_at": live_bundle.get("updated_at"),
            "tracked_count": len(live_bundle.get("rows_by_symbol", {})),
            "errors": live_bundle.get("errors", []),
            "source_mode": live_bundle.get("source_mode", "empty"),
            "fallback_symbols": live_bundle.get("fallback_symbols", []),
            "provider_counts": provider_counts,
            "provider_summary": provider_summary,
        },
        "macro": {
            "updated_at": macro_bundle.get("updated_at"),
            "topics": macro_topics,
            "errors": macro_bundle.get("errors", []),
            "source_mode": macro_bundle.get("source_mode", "empty"),
        },
        "source_health": source_health,
        "methodology": {
            "ai_engine": ai_insights.get("engine") or fallback_ai_engine_meta(),
            "market_data": {
                "history_window_days": HISTORY_POINTS,
                "provider_counts": provider_counts,
                "provider_summary": provider_summary,
                "fallback_rule": "在线行情失败时先回退到本地日更快照，再兜底为结单价格。",
            },
        },
        "ai_insights": ai_insights,
        "key_drivers": key_drivers,
        "risk_flags": risk_flags,
        "accounts": account_cards,
        "breakdowns": {
            "themes": theme_breakdown,
            "markets": market_breakdown,
            "brokers": broker_breakdown,
        },
        "charts": {
            "theme_donut": theme_breakdown,
            "broker_risk": build_broker_risk_chart(account_cards, derivatives),
            "holding_scatter": build_scatter_points(holdings),
            "performance": build_performance_chart(holdings),
            "health_radar": build_health_radar(
                holdings,
                portfolio["total_nav_hkd"],
                portfolio["total_financing_hkd"],
                total_derivative_notional_hkd,
                portfolio["top5_ratio"],
            ),
            "style_mix": build_style_mix_chart(holdings),
            "signal_heatmap": build_signal_heatmap(holdings),
            "price_regime": build_price_regime_chart(holdings),
            "macro_topics": macro_topics,
        },
        "holdings": holdings,
        "top_holdings": holdings[:10],
        "fundamental_deep_dive": fundamental_deep_dive,
        "trades": trades[:12],
        "derivatives": derivatives,
        "strategy_views": strategy_views,
        "brief": {
            "headline": headline,
            "overview": overview,
            "priority_actions": build_priority_actions(
                holdings,
                trades,
                portfolio["total_financing_hkd"],
                total_derivative_notional_hkd,
                portfolio["total_nav_hkd"],
                macro_topics,
            ),
            "framework": REFERENCE_FRAMEWORK,
            "holding_notes": holding_notes,
            "disclaimer": "以下内容用于辅助复盘、跟踪和风险管理，不构成个性化投顾承诺。",
        },
        "update_guide": [
            "上传新结单后，对应账户的持仓、交易和账户汇总会立即更新。",
            f"刷新后会同步最新价格、近 {HISTORY_POINTS} 日走势和组合提示。",
            "建议先看总览，再到持仓和账户页逐项确认重点变化。",
            "页面更适合做仓位复盘、集中度监控、融资/衍生品风险管理和个股跟踪。",
        ],
        "statement_sources": monitored_statements(accounts, user_id=user_id),
        "reference_sources": [
            {
                "label": item["label"],
                "type": item["type"],
                "file_name": Path(item["path"]).name,
            }
            for item in get_reference_analysis_sources(user_id=user_id)
        ],
    }


def build_dashboard_ai_payload_from_snapshot(
    snapshot_payload: dict[str, Any],
    ai_request_config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    summary = snapshot_payload.get("summary") or {}
    macro = snapshot_payload.get("macro") or {}
    holdings = snapshot_payload.get("holdings") or []
    trades = snapshot_payload.get("trades") or []
    derivatives = snapshot_payload.get("derivatives") or []

    ai_insights = (
        build_ai_insights(
            holdings,
            trades,
            derivatives,
            float(summary.get("total_nav_hkd") or 0.0),
            float(summary.get("total_financing_hkd") or 0.0),
            float(summary.get("total_derivative_notional_hkd") or 0.0),
            macro.get("topics") or [],
            ai_request_config=ai_request_config,
        )
        if holdings
        else empty_ai_insights()
    )

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "analysis_date_cn": snapshot_payload.get("analysis_date_cn") or now_cn_date(),
        "snapshot_date": snapshot_payload.get("snapshot_date"),
        "methodology": {
            "ai_engine": ai_insights.get("engine") or fallback_ai_engine_meta(),
        },
        "ai_insights": ai_insights,
        "ai_status": {
            "state": "ready",
            "message": "AI 洞察已更新，已结合组合结构、近期交易和风险预算完成分析。",
        },
    }


def validate_payload(payload: dict[str, Any], user_id: str | None = None) -> list[str]:
    errors = []
    summary = payload["summary"]
    if summary["account_count"] != len(get_statement_sources(user_id=user_id)):
        errors.append("account count mismatch")
    if summary["holding_count"] < 20:
        errors.append("too few holdings")
    if summary["trade_count"] < 5:
        errors.append("too few trades")
    if summary["derivative_count"] < 8:
        errors.append("too few derivatives")
    if not payload["brief"]["priority_actions"]:
        errors.append("missing priority actions")
    if len(payload["brief"]["holding_notes"]) != summary["holding_count"]:
        errors.append("holding notes mismatch")
    if "charts" not in payload:
        errors.append("missing charts")
    return errors
