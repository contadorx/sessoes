# Como abrir uma build no Claude Code

*Para o Leandro. Não é para o Code ler — é o que você cola nele.*

---

## O ritual, e ele é curto

O `CLAUDE.md` da raiz é lido sozinho a cada sessão. O arquivo da build **é** o
prompt. Então abrir uma build é isto:

```
Leia docs/builds/B48-o-campo-faz-o-que-ela-digitou.md e execute.

Regras que valem antes de qualquer linha:
- confira cada achado do arquivo contra o código antes de consertar; se algum
  não se reproduzir, pare e me diga qual;
- ao mexer em função do banco, leia o banco (pg_get_functiondef), não a migração;
- a build só fecha com o critério de "pronto quando" verificado RODANDO;
- rode `npm run verificar` e as suítes que a mudança toca, não as que tratam do
  mesmo assunto.

Comece listando o que você vai fazer, na ordem, e espere meu ok.
```

Trocar o nome do arquivo é a única coisa que muda de uma build para outra.

---

## O que fazer quando o Code discordar do arquivo

Os achados foram levantados por leitura de código e consulta ao banco de
produção, **sem o app rodando**. Três coisas podem acontecer:

**O achado não se reproduz.** Aconteceu uma mudança depois de 02/09, ou a leitura
estava errada. Peça a evidência (`arquivo:linha` atual) e risque o item — não
deixe o Code "consertar" o que não está quebrado.

**O achado é maior do que o arquivo diz.** Aí ele vira achado novo, com
severidade. S1 e S2 param a build e viram linha nova; S3 e S4 vão para a
**B47**.

**O Code propõe uma solução que atravessa uma fronteira.** Acontece, e o
`CLAUDE.md` seção 3 e 4 existe para isso. A resposta não é negociar o escopo: é
reformular o achado.

---

## Ao fim de cada build, três linhas para o diário

O projeto tem um diário de bordo (`claude/14-diario-de-bordo.md`) e ele é onde as
lições moram — não no cabeçalho da migração, que já se provou o formato errado
(a mesma lição foi repetida catorze migrações depois pela mesma pessoa).

Peça ao Code, ao fechar:

```
Escreva três linhas para o diário: o que a build consertou, o defeito que ela
achou de passagem, e a lição que vale para a próxima. Sem elogio.
```

---

## A ordem, para não ter que abrir o README

```
1  B48  o campo faz o que ela digitou      3     ← dois S1
2  B43  a mensagem diz onde está           2     ← dois S1
3  B44  um mês, um número                  2     ← um S1
4  B39  evolução por ditado                3     ← um S1
5  B46  a quarta varredura                 1
6  B45  a segunda-feira de manhã           1,5
7  P7   página transacional única          2
8  P8   assistente do Receita Saúde        1
9  B31  plano terapêutico e encerramento   2,5
10 B32  documentos da Res. 06/2019         3,5
11 B47  o dia dela custa menos toques      2,5
12 B36  reajuste e modo férias             3
13 B34  pré-ficha administrativa           2
14 OP7  suporte com chamados               —     ← só quando o e-mail não der conta
```

**Os quatro primeiros são 10 dias e fecham os seis S1.** Se o tempo apertar, o
que sai é do fim para o começo — nunca do começo.
