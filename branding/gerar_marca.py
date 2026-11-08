"""Gera a marca do RodaJusta (SVG) e os ícones PNG dos dois apps.

Conceito: uma roda dividida em seis partes iguais (a divisão justa do
trabalho) com uma das partes destacada em âmbar: "a vez" de alguém no
rodízio. O cubo central é o ponto de partida, a loja.

Uso: python3 branding/gerar_marca.py   (precisa do rsvg-convert)
"""
import math
import os
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)

CORES = {
    "verde": "#0F6B4F",
    "verde_escuro": "#0A4D39",
    "ambar": "#F5B700",
    "tinta": "#10221B",
    "branco": "#FFFFFF",
}

C, R, LARG = 256, 150, 38  # centro, raio do aro, espessura do aro
HUB = 42


def ponto(ang_graus, raio):
    a = math.radians(ang_graus)
    return C + raio * math.cos(a), C + raio * math.sin(a)


def arco(a0, a1, raio):
    x0, y0 = ponto(a0, raio)
    x1, y1 = ponto(a1, raio)
    grande = 1 if (a1 - a0) % 360 > 180 else 0
    return f"M{x0:.2f} {y0:.2f} A{raio} {raio} 0 {grande} 1 {x1:.2f} {y1:.2f}"


def marca(fundo, aro, destaque, cubo, com_fundo=True, raio_fundo=112):
    partes = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">']
    if com_fundo:
        partes.append(f'<rect width="512" height="512" rx="{raio_fundo}" fill="{fundo}"/>')
    # raios: 6 divisões iguais, começando no topo
    for i in range(6):
        ang = -90 + i * 60
        x0, y0 = ponto(ang, HUB + 6)
        x1, y1 = ponto(ang, R - LARG / 2 + 2)
        partes.append(
            f'<line x1="{x0:.2f}" y1="{y0:.2f}" x2="{x1:.2f}" y2="{y1:.2f}" '
            f'stroke="{aro}" stroke-width="20" stroke-linecap="round"/>'
        )
    partes.append(
        f'<circle cx="{C}" cy="{C}" r="{R}" fill="none" stroke="{aro}" stroke-width="{LARG}"/>'
    )
    # a parte da vez: um sexto do aro em destaque
    partes.append(
        f'<path d="{arco(-90, -30, R)}" fill="none" stroke="{destaque}" '
        f'stroke-width="{LARG + 2}" stroke-linecap="butt"/>'
    )
    partes.append(f'<circle cx="{C}" cy="{C}" r="{HUB}" fill="{cubo}"/>')
    partes.append("</svg>")
    return "\n".join(partes)


VARIANTES = {
    # app Operação: verde com aro branco
    "operacao": marca(CORES["verde"], CORES["branco"], CORES["ambar"], CORES["ambar"]),
    # app Admin: tinta escura, mesma marca, cubo verde para diferenciar
    "admin": marca(CORES["tinta"], CORES["branco"], CORES["ambar"], CORES["verde"]),
    # marca sem fundo para usar dentro dos apps e no README
    "marca": marca(None, CORES["verde"], CORES["ambar"], CORES["ambar"], com_fundo=False),
}

DENSIDADES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def png(svg_path, saida, tamanho):
    os.makedirs(os.path.dirname(saida), exist_ok=True)
    subprocess.run(
        ["rsvg-convert", "-w", str(tamanho), "-h", str(tamanho), "-o", saida, svg_path],
        check=True,
    )


def main():
    for nome, svg in VARIANTES.items():
        caminho = os.path.join(AQUI, f"{nome}.svg")
        with open(caminho, "w", encoding="utf-8") as f:
            f.write(svg)

    for app in ("operacao", "admin"):
        svg = os.path.join(AQUI, f"{app}.svg")
        res = os.path.join(RAIZ, "apps", app, "android", "app", "src", "main", "res")
        for dens, px in DENSIDADES.items():
            png(svg, os.path.join(res, f"mipmap-{dens}", "ic_launcher.png"), px)
        png(svg, os.path.join(AQUI, f"{app}-512.png"), 512)
        # logo usado nas telas do app
        png(os.path.join(AQUI, "marca.svg"), os.path.join(RAIZ, "apps", app, "assets", "marca.png"), 384)
    png(os.path.join(AQUI, "marca.svg"), os.path.join(AQUI, "marca-256.png"), 256)


if __name__ == "__main__":
    main()
