import os
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, KeepTogether, HRFlowable
)
from reportlab.pdfgen import canvas

class NumberedCanvas(canvas.Canvas):
    def __init__(self, *args, **kwargs):
        super(NumberedCanvas, self).__init__(*args, **kwargs)
        self._saved_page_states = []

    def showPage(self):
        self._saved_page_states.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        num_pages = len(self._saved_page_states)
        for state in self._saved_page_states:
            self.__dict__.update(state)
            self.draw_page_decorations(num_pages)
            super(NumberedCanvas, self).showPage()
        super(NumberedCanvas, self).save()

    def draw_page_decorations(self, page_count):
        self.saveState()
        self.setFont("Helvetica", 9)
        self.setFillColor(colors.HexColor("#718096"))
        
        # Header (pages > 1)
        if self._pageNumber > 1:
            self.drawString(54, 750, "AsianFX Platform Architecture & Operational Workflow Guide")
            self.setStrokeColor(colors.HexColor("#E2E8F0"))
            self.setLineWidth(0.8)
            self.line(54, 742, letter[0] - 54, 742)
        
        # Footer
        footer_text = f"Page {self._pageNumber} of {page_count}"
        self.drawRightString(letter[0] - 54, 36, footer_text)
        self.drawString(54, 36, "CONFIDENTIAL & PROPRIETARY — ASIANFX TRADING SYSTEM")
        self.setStrokeColor(colors.HexColor("#E2E8F0"))
        self.setLineWidth(0.8)
        self.line(54, 48, letter[0] - 54, 48)
        self.restoreState()

def create_pdf(filename="AsianFX_App_Process_and_Workflow_Guide.pdf"):
    doc = SimpleDocTemplate(
        filename,
        pagesize=letter,
        leftMargin=54,
        rightMargin=54,
        topMargin=54,
        bottomMargin=54
    )

    styles = getSampleStyleSheet()
    
    # Custom color palette
    c_primary = colors.HexColor("#0F172A")    # Deep Slate
    c_accent = colors.HexColor("#3B82F6")     # Royal Blue
    c_success = colors.HexColor("#10B981")    # Emerald Green
    c_text = colors.HexColor("#1E293B")       # Dark Charcoal
    c_muted = colors.HexColor("#64748B")      # Slate Muted
    c_bg_light = colors.HexColor("#F8FAFC")   # Light background
    c_card_border = colors.HexColor("#E2E8F0")

    # Typography styles
    title_style = ParagraphStyle(
        'DocTitle',
        parent=styles['Heading1'],
        fontName='Helvetica-Bold',
        fontSize=24,
        leading=28,
        textColor=c_primary,
        spaceAfter=6
    )
    
    subtitle_style = ParagraphStyle(
        'DocSubtitle',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=12,
        leading=16,
        textColor=c_accent,
        spaceAfter=15
    )

    h1_style = ParagraphStyle(
        'Heading1_Custom',
        parent=styles['Heading1'],
        fontName='Helvetica-Bold',
        fontSize=16,
        leading=20,
        textColor=c_primary,
        spaceBefore=14,
        spaceAfter=8,
        keepWithNext=True
    )

    h2_style = ParagraphStyle(
        'Heading2_Custom',
        parent=styles['Heading2'],
        fontName='Helvetica-Bold',
        fontSize=12,
        leading=16,
        textColor=c_accent,
        spaceBefore=10,
        spaceAfter=4,
        keepWithNext=True
    )

    body_style = ParagraphStyle(
        'Body_Custom',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=10,
        leading=14,
        textColor=c_text,
        spaceAfter=8
    )

    bullet_style = ParagraphStyle(
        'Bullet_Custom',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=9.5,
        leading=13.5,
        textColor=c_text,
        leftIndent=15,
        spaceAfter=4
    )

    callout_style = ParagraphStyle(
        'Callout_Text',
        parent=styles['Normal'],
        fontName='Helvetica-Oblique',
        fontSize=9.5,
        leading=13.5,
        textColor=colors.HexColor("#1E3A8A")
    )

    table_header_style = ParagraphStyle(
        'TableHeader',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=9,
        leading=11,
        textColor=colors.white
    )

    table_cell_style = ParagraphStyle(
        'TableCell',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=8.5,
        leading=11,
        textColor=c_text
    )

    elements = []

    # Title Block
    elements.append(Paragraph("AsianFX Trading System", title_style))
    elements.append(Paragraph("Platform Architecture, Market Maker Engine & Operational Process Guide", subtitle_style))
    elements.append(HRFlowable(width="100%", thickness=2, color=c_accent, spaceAfter=14))

    # Executive Overview
    elements.append(Paragraph("1. Executive Overview", h1_style))
    elements.append(Paragraph(
        "<b>AsianFX</b> is a high-performance multi-asset trading platform supporting Crypto, Forex, and Precious Metals. "
        "The architecture combines a Flutter mobile client, real-time WebSocket market feeds, and a secure Supabase PostgreSQL backend "
        "powered by Atomic Stored Procedures (RPCs) and Double-Entry Ledger Accounting. The system operates as a hybrid Market Maker (B-Book / A-Book) "
        "allowing internal order matching with dynamic USD Margin Hold and real-time risk settlement.",
        body_style
    ))

    # Key Specifications Table
    spec_data = [
        [Paragraph("Component", table_header_style), Paragraph("Technology / Mechanism", table_header_style), Paragraph("Key Role", table_header_style)],
        [Paragraph("Mobile Client", table_cell_style), Paragraph("Flutter (Dart 3.x) + Riverpod", table_cell_style), Paragraph("Interactive UI, Candlestick Charts, 2FA/Vault", table_cell_style)],
        [Paragraph("Market Feed", table_cell_style), Paragraph("Binance WebSocket + Synthetic Ticker", table_cell_style), Paragraph("Sub-second live prices with dealer spread markups", table_cell_style)],
        [Paragraph("Trading Engine", table_cell_style), Paragraph("Supabase PostgreSQL RPCs + ACID Locks", table_cell_style), Paragraph("Atomic margin lock, trade validation, PnL settlement", table_cell_style)],
        [Paragraph("Accounting", table_cell_style), Paragraph("Double-Entry Ledger Architecture", table_cell_style), Paragraph("Auditable margin lock, margin release, realized PnL", table_cell_style)],
        [Paragraph("Security", table_cell_style), Paragraph("Row Level Security (RLS) + SHA-256 / AES", table_cell_style), Paragraph("Anti-tamper protection, user-isolated data access", table_cell_style)]
    ]
    spec_table = Table(spec_data, colWidths=[100, 190, 214])
    spec_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), c_primary),
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
        ('TOPPADDING', (0, 0), (-1, -1), 6),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [c_bg_light, colors.white]),
        ('GRID', (0, 0), (-1, -1), 0.5, c_card_border),
    ]))
    elements.append(spec_table)
    elements.append(Spacer(1, 14))

    # Architecture & End-to-End Workflow
    elements.append(Paragraph("2. End-to-End Operational Workflow", h1_style))
    elements.append(Paragraph("The platform executes trading operations through four synchronized phases:", body_style))
    
    elements.append(Paragraph("<b>Step 1: Real-Time Price Ingestion & Spread Markup</b>", h2_style))
    elements.append(Paragraph(
        "• Raw price streams arrive from Binance WebSockets (e.g. BTC, ETH, SOL) and institutional metal/forex tickers.<br/>"
        "• The dealer desk injects customizable pip markups (e.g., +15 pips for XAU/USD, +40 pips for BTC/USD) to generate Bid/Ask prices for retail traders.<br/>"
        "• Real-time price ticks stream simultaneously to the Candlestick Chart and Open Trade Floating PnL engine.",
        bullet_style
    ))

    elements.append(Paragraph("<b>Step 2: Order Placement & USD Margin Hold (Lock)</b>", h2_style))
    elements.append(Paragraph(
        "• Trader submits a Buy or Sell order specifying symbol, lot size, leverage, stop-loss, and take-profit.<br/>"
        "• The system calculates <b>Required Margin</b>: <i>(Lots × Contract Size × Price) / Leverage</i>.<br/>"
        "• <b>Atomic Pre-Flight Check:</b> If <i>Free Margin = (Balance - Held Margin) ≥ Required Margin</i>, the order proceeds.<br/>"
        "• <b>USD Hold Lock:</b> Supabase PostgreSQL RPC (<code>rpc_open_trade</code>) executes inside an ACID transaction to lock <code>held_margin += Required Margin</code> and inserts the trade record.",
        bullet_style
    ))

    elements.append(Paragraph("<b>Step 3: Real-Time Risk & Floating PnL Monitoring</b>", h2_style))
    elements.append(Paragraph(
        "• On every tick, floating PnL is computed: <i>(Current Price - Open Price) × Lots × Contract Size</i> for Buy trades.<br/>"
        "• <b>Equity = Balance + Total Floating PnL</b>.<br/>"
        "• <b>Margin Level = (Equity / Used Margin) × 100%</b>.<br/>"
        "• <b>Margin Call Alert (100%):</b> Trader receives high-priority warning.<br/>"
        "• <b>Stop-Out Auto-Liquidation (50%):</b> Server closes the worst-performing trade to protect platform and trader equity.",
        bullet_style
    ))

    elements.append(Paragraph("<b>Step 4: Position Settlement & Margin Release</b>", h2_style))
    elements.append(Paragraph(
        "• When closed (manually, by Stop-Loss / Take-Profit, or Liquidation), <code>rpc_close_trade</code> is invoked.<br/>"
        "• <b>Margin Release:</b> <code>held_margin = held_margin - Required Margin</code> (USD unlocked).<br/>"
        "• <b>Cash Settlement:</b> <code>balance = balance + Realized PnL</code>.<br/>"
        "• Immutable ledger entry is written with exact timestamps and reference IDs.",
        bullet_style
    ))

    elements.append(Spacer(1, 10))

    # Margin Formula & Balance State Matrix
    elements.append(Paragraph("3. Financial Math & Balance State Model", h1_style))
    
    math_data = [
        [Paragraph("Metric", table_header_style), Paragraph("Mathematical Formula", table_header_style), Paragraph("Example Simulation ($10k Account)", table_header_style)],
        [Paragraph("Balance (Cash)", table_cell_style), Paragraph("Deposits - Withdrawals + Realized PnL", table_cell_style), Paragraph("$10,000.00 USD (Liquid Capital)", table_cell_style)],
        [Paragraph("Required Margin", table_cell_style), Paragraph("(Lots × Contract Size × Price) / Leverage", table_cell_style), Paragraph("0.1 BTC @ $60,000 / 100x = <b>$60.00 USD (HOLD)</b>", table_cell_style)],
        [Paragraph("Held Margin", table_cell_style), Paragraph("Sum of all open trades' Required Margin", table_cell_style), Paragraph("<b>$60.00 USD (Locked in Vault)</b>", table_cell_style)],
        [Paragraph("Floating PnL", table_cell_style), Paragraph("Δ Price × Lots × Contract Size", table_cell_style), Paragraph("+$40.00 USD (Unrealized Profit)", table_cell_style)],
        [Paragraph("Equity", table_cell_style), Paragraph("Balance + Floating PnL", table_cell_style), Paragraph("$10,040.00 USD", table_cell_style)],
        [Paragraph("Free Margin", table_cell_style), Paragraph("Equity - Held Margin", table_cell_style), Paragraph("<b>$9,980.00 USD</b> (Available to trade/withdraw)", table_cell_style)],
        [Paragraph("Margin Level %", table_cell_style), Paragraph("(Equity / Held Margin) × 100", table_cell_style), Paragraph("<b>16,733%</b> (Healthy > 100%)", table_cell_style)]
    ]
    math_table = Table(math_data, colWidths=[100, 200, 204])
    math_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), c_accent),
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [c_bg_light, colors.white]),
        ('GRID', (0, 0), (-1, -1), 0.5, c_card_border),
    ]))
    elements.append(math_table)
    elements.append(Spacer(1, 14))

    # Market Maker Model & Economics
    elements.append(Paragraph("4. Market Maker (B-Book / Dealing Desk) Mechanism", h1_style))
    elements.append(Paragraph(
        "AsianFX operates as a <b>Dealing Desk / Market Maker Broker</b>. Understanding how revenue is generated and risk is managed:",
        body_style
    ))
    elements.append(Paragraph(
        "<b>1. Internal Counterparty Matching (B-Book):</b> When retail traders open positions, the platform acts as the direct counterparty. Trades do not incur external exchange fees, providing instant fill execution without external slippage.<br/>"
        "<b>2. Spread Revenue:</b> The platform captures risk-free revenue on every trade via the Bid/Ask spread markup.<br/>"
        "<b>3. Hybrid A-Book Risk Hedging:</b> If a trader holds large profitable exposure or a high-volume market event occurs, the broker can route hedging orders to external liquidity providers (LPs/Binance) to cap platform downside risk.<br/>"
        "<b>4. Double-Entry Security:</b> User balances are strictly separated between Available Capital and Trade Collateral Escrow.",
        bullet_style
    ))

    elements.append(Spacer(1, 10))

    # Security & Production Readiness
    elements.append(Paragraph("5. Security & Verification Status", h1_style))
    elements.append(Paragraph(
        "• <b>Atomic ACID Transactions:</b> All balance modifications and margin locks occur inside PostgreSQL Stored Procedures (<code>rpc_open_trade</code>, <code>rpc_close_trade</code>).<br/>"
        "• <b>Row Level Security (RLS):</b> PostgreSQL enforces strict tenant isolation using <code>auth.uid()</code>.<br/>"
        "• <b>Client-Side Safety:</b> App handles offline gracefully while enforcing authoritative backend truth.<br/>"
        "• <b>Audit Trail:</b> Every financial event generates an unalterable record in the <code>ledger_entries</code> table.",
        bullet_style
    ))

    # Callout Box
    callout_data = [[
        Paragraph(
            "<b>Deployment Note:</b> The Supabase database schema (<code>supabase_schema.sql</code>) has been successfully verified. "
            "The client APK can be generated via <code>flutter build apk --release</code> for staging and user testing.",
            callout_style
        )
    ]]
    callout_table = Table(callout_data, colWidths=[504])
    callout_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, -1), colors.HexColor("#EFF6FF")),
        ('BORDER', (0, 0), (-1, -1), 1, colors.HexColor("#BFDBFE")),
        ('LEFTPADDING', (0, 0), (-1, -1), 12),
        ('RIGHTPADDING', (0, 0), (-1, -1), 12),
        ('TOPPADDING', (0, 0), (-1, -1), 8),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
    ]))
    elements.append(Spacer(1, 8))
    elements.append(callout_table)

    # Build Document
    doc.build(elements, canvasmaker=NumberedCanvas)
    print(f"PDF successfully created: {filename}")

if __name__ == "__main__":
    create_pdf()
