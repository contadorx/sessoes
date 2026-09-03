# Sessões — o que você precisa saber antes de tocar em qualquer coisa

Este arquivo é lido a cada sessão. Ele não descreve o código: descreve as
**decisões que o código não pode contrariar**. Quando este arquivo e o código
discordarem, é o código que está errado — abra um achado, não uma exceção.

> **O `README.md` da raiz está desatualizado.** Ele descreve a tese antiga
> ("sua agenda não fura mais de graça"), chama o repositório de "landing" e cita
> um simulador de ROI que foi removido por decisão. Use este arquivo; corrija o
> README quando passar por ele.

---

## 1 · O produto, em uma frase

**Sessões organiza tudo o que não é atender**: a agenda, os recebimentos, os
recibos e o fechamento do mês com o contador. E mostra **quanto da capacidade
disponível virou receita — e por onde o resto foi.**

E a metade da frase que define o produto contra o que seria fácil construir:
**sem decidir frequência clínica, sem reativar ex-paciente e sem definir preço
promocional.**

O produto tem quatro núcleos, nesta ordem: o **livro-razão da sessão** (cinco
eixos independentes: agenda, confirmação, financeiro, fiscal, capacidade) · a
**cobrança e a conciliação** · o **fiscal** (Receita Saúde PF/PJ) · a
**capacidade declarada** (as horas que ela decidiu disponibilizar). Feature que
não cai num desses entra sob suspeita. O prontuário é **paridade bem-feita** —
necessário para não ser descartado, nunca o argumento.

---

## 2 · Quem é a usuária — não invente outra

Não escreva "o usuário". A pessoa é uma:

- **Psicóloga autônoma**, 40–80 sessões por mês, presencial e online misturados.
- **O celular é o dispositivo principal.** PWA, mobile-first. Ela abre o app
  **entre uma sessão e outra**, de pé, com dez minutos, às vezes com a próxima
  paciente na sala de espera. **375 px é a largura de projeto.**
- **Ela se descreve como ruim com números.** Isso é dado de campo. Tela que
  cobra dela um número que ela não tem não é neutra: é acusação.
- **Ela tem medo de expor paciente.** O modo discreto existe por isso.
- **O que ela já faz hoje funciona para ela**: caderno, WhatsApp, planilha,
  Word. Se a sua tela for mais lenta que o caderno, o caderno ganha.
- **Ela não vai ler documentação, não vai ver tour e não vai voltar depois.** O
  que não se explica na própria tela não se explica.

**A segunda persona, que a auditoria costuma esquecer:** a **secretária ou sócia
de clínica, sem acesso clínico**. Todo caminho tem que ser percorrido também com
a pergunta *"e se quem estiver aqui não puder ler prontuário?"*.

---

## 3 · As onze fronteiras — nenhuma se atravessa, nem em nome de usabilidade

1. **Não entra na sala.** Nada de gravar paciente, transcrever sessão, IA
   opinando, sugerindo diagnóstico, conduta ou risco.
2. **Não é marketplace.** Não vende paciente, não rankeia profissional.
3. **Não é plataforma de testes** (SATEPSI) nem prescreve instrumento.
4. **Não é ERP.** Sem conciliação bancária, contas a pagar, boleto, DRE, folha.
5. **A fila nunca vira leilão.** Prioridade é regra clínica dela; dinheiro não
   compra posição.
6. **Perguntas clínicas não vão por formulário ao paciente.** Pré-ficha é
   administrativa.
7. **O contador recebe finanças, nunca clínica.**
8. **Sem integração por prefeitura** na NFS-e fora do padrão nacional, e **sem
   Evolution / API não-oficial de WhatsApp**.
9. **Dado clínico não vai para ambiente de teste**, prompt de IA externa sem
   contrato, ou ferramenta de suporte.
10. **Roadmap não fura portão.**
11. **O Sessões não guarda credencial gov.br e não emite no lugar dela.** Nem
    senha, nem sessão, nem token, nem por intermediador. O que existe e basta é
    o arquivo em lote do Carnê-Leão.

**E a mais afiada, que vem do Código de Ética:** *frequência clínica não é
decisão de software.* Qualquer coisa que sugira que alguém "podia vir mais" é
juízo clínico tomado por razão financeira. Ficam vedados pela mesma linha:
reativação de ex-paciente com preço menor, preço promocional last-minute e
remuneração por encaminhamento. O que sobra e é legítimo: mostrar que a cadência
**combinada** não aconteceu — fato administrativo, sem conclusão.

---

## 4 · O que está morto e não volta

Registrado para ninguém reabrir por engano: **B30** (briefing de 30s) · **D12**
(radar de furo) · **D8** (alerta de sumiço) · **D10** (fila cruzada) · **D17**
(encaminhamento remunerado) · **N1/N2/N5** (QR, modelos por abordagem, check-in
clínico) · **D18** (portal do paciente — virou o P7) · **B38** (NFS-e PJ, saiu
da fila em 02/09) · **B12b** (link de agendamento — vira rota do P7) ·
**emitir o Receita Saúde no lugar dela** (fronteira 11).

**Também nunca entra:** gamificação, streak, badge, parabéns por meta ·
simulador de ROI ou número projetado como argumento de tela · impersonação ou
leitura de prontuário pelo suporte, em qualquer forma.

Se um achado seu parecer pedir uma dessas, o achado está mal formulado.

---

## 5 · O vocabulário — escolha de palavra é decisão de produto

| não use | use |
|---|---|
| "recuperar a hora" | **onde o dinheiro parou** |
| "reativar paciente" | *(não existe)* |
| "inadimplente" | **em aberto** |
| "abaixo do piso do CFP" | **abaixo do valor de referência** |
| "otimizar ocupação" | **quanto da capacidade virou receita** |
| "operação financeira" | **o que não é atender** |
| "perdeu o horário" | **horário não ocupado** |

**A regra da OP10:** o código do sistema (`gratis`, `solo`, `pro`, `clinica`)
**nunca aparece para ela**; o nome (Gratuito, Consultório, Consultório Completo,
Clínica) nunca aparece numa chave estrangeira.

**Jargão do sistema que não pode ser rótulo de tela:** *eixo · livro-razão ·
cockpit · capacidade vendável · completude · lastro · régua · materializar ·
faixa* (quando significa cota de plano). Se você precisar do termo, escreva a
consequência: "o que aconteceu com cada hora", "o que dá base à cobrança", "ver
quem está devendo", "montada até 27/10".

---

## 6 · Tom de voz — normativo, não sugestão

- Fala **com** a profissional, nunca pelo paciente.
- **Não cobra número dela.** Nenhuma frase pergunta algo que ela não sabe
  responder sobre o próprio consultório.
- **Descreve o horário sem julgar a ausência.**
- **Automação condicional se diz condicional.** "O Pix é comparado com as
  sessões previstas", não "o Pix encontra a sessão sozinho". No plano Gratuito o
  canal é **manual** — nenhuma tela pode dizer que o sistema oferece "sozinho".
- **Zero jargão de startup** ("alavancar", "otimizar sua operação", "dashboard",
  "insights", "engajamento", "performance").
- **Zero linguagem terapêutica de marketing** ("acolher", "cuidar de quem
  cuida").
- **Sem meta, sem alvo, sem cor que melhora quando o número sobe.** Nenhuma
  palavra de elogio ou parabéns. Há verificação no P5 que reprova isso.
- **Não escreva a decisão de projeto na tela de tarefa.** "É de propósito", "é
  decisão", "o Manual pede", "nem por você" pertencem ao diário, não ao
  formulário que ela preenche de pé. (Doze ocorrências disso foram achadas na
  auditoria; não acrescente a décima terceira.)

**O check do público:** cada frase da interface se explica para uma psicóloga em
uma frase? Se não, é candidata a estar errada.

---

## 7 · As leis de engenharia

Cinco vêm das cicatrizes do FinanceiroX; três vieram da auditoria de 02/09.

1. **`supabase-js` não lança erro.** Toda operação passa por `db()` de
   `lib/db.ts`, que loga com contexto e **lança**. O ESLint reprova o import
   direto de `@supabase/supabase-js` fora de `lib/supabase/`.
2. **RLS desde a primeira tabela.** Função `security definer` sempre com
   `search_path` fixado; políticas com `(select auth.uid())`; FK sempre
   indexada.
3. **Fuso é decisão.** Tudo que é "dia" se calcula em `America/Sao_Paulo`, no
   banco, por `hoje_sp()`. `toISOString()` num horário de 21h dá o dia seguinte.
4. **Dinheiro em `numeric`, nunca float.** Na aplicação, centavos inteiros
   (`lib/dinheiro.ts`). Sinal é contrato.
5. **Migração é arquivo versionado no repo.** Nada se aplica no Supabase que não
   esteja em `supabase/migrations/`.
6. **Ao reescrever uma função do banco, leia o BANCO e não a migração.** Este
   projeto foi mordido **três vezes** por isso — `avancar_fila` perdeu a linha
   que enfileira a mensagem duas vezes (0046d e 0060d), e `exportar_conta`
   parou de se registrar na trilha em duas builds seguidas. Use
   `pg_get_functiondef` ou o painel; a migração mais recente pode não ser o que
   está rodando.
7. **Nunca verifique por lista escrita à mão.** Toda checagem por enumeração
   deixa passar o item novo: `exportar_conta` esqueceu 17 tabelas porque a lista
   era de quando havia doze. Varra o `information_schema`, o `pg_proc`, o
   catálogo — não uma constante. **Na UI o equivalente é a tela que enumera
   tipos e some com o tipo que ninguém previu.**
8. **Adaptador ausente recusa, não finge.** `lib/calendario/adaptadores.ts`
   declara `disponivel: false` e explica; a mensageria fingiu que enviou e virou
   S1. Sem provedor configurado, o caminho é dizer que não saiu.

---

## 8 · Como se trabalha aqui

- **Uma build por vez, na ordem de `docs/builds/README.md`.** O arquivo de cada
  build **é** o prompt de abertura dela: entrega, pronto-quando e não-entra são
  o escopo fechado. Build que não passa no critério de pronto não abre a
  seguinte.
- **Critério de pronto se verifica rodando, não lendo.**
- **Cada build acrescenta a suíte adversarial dela e roda as suítes antigas que
  ela toca.** O critério de regressão é **que funções a migração reescreve**,
  não que assunto ela trata. Os últimos oito defeitos apareceram assim, e nenhum
  foi encontrado lendo código.
- **A suíte prova o contrário quando a decisão muda.** Quando o P4 tirou a
  cobrança automática, a suíte 0022 foi reescrita para provar o oposto do que
  provava. Isso é o esperado, não um problema.
- **Não proponha tela nova onde cabe frase.** Este produto já tem telas demais
  competindo pela segunda-feira de manhã dela.

### Comandos

```bash
npm run dev          # desenvolvimento
npm run verificar    # lint + tsc --noEmit + vitest — roda antes de qualquer commit
npm run test         # só os testes unitários
```

Suítes SQL: `supabase/tests/*.sql` (45 hoje). Migrações:
`supabase/migrations/*.sql` (103 aplicadas). **Próxima migração livre: `0066`.**

### Estrutura

```
app/(site)/        páginas públicas — landing, termos, privacidade, segurança,
                   incidente, blog
app/(app)/         a área autenticada: agenda, encaixes, pacientes,
                   recebimentos, fechamento, perfil, comecar, buscar, negocio
app/p/             páginas transacionais por link mágico (contrato, remarcar)
app/api/           mensageria, diario, pagamentos, whatsapp (crons e webhooks)
components/app/    os componentes da área autenticada
components/site/   os componentes das páginas públicas
lib/               regra pura e testada — é aqui que a decisão mora
lib/db.ts          o helper db() — a lei nº 1
proxy.ts           a lista de rotas públicas; toda página de app/(site) precisa
                   passar por ehPublica
supabase/          migrations e tests
```

### A navegação, e o que a destruiria

`lib/navegacao.ts` é puro, testado e carrega a decisão: **cinco destinos**
(Agenda · Encaixes · Pacientes · Recebimentos · Fechamento), e o que não é
destino fica à direita (buscar, Novo, perfil). **No celular o teto é cinco
cadeiras.** Não acrescente um sexto item de menu; não devolva "Receita" e
"Contador" a destino permanente — eles viraram a faixa de pendências, que só
existe quando há prazo correndo.

---

## 9 · Os antipadrões deste projeto — procure por nome

Cada um já apareceu aqui mais de uma vez:

- **A segunda fonte de verdade.** Dois lugares respondendo à mesma pergunta com
  números diferentes. **Sobre dinheiro, isso é S1 automático.**
- **A lista escrita à mão** (lei 7).
- **A tela que admite ser palpite.** O "número 3" do aviso de anamnese diz na
  cara que é chute.
- **O filtro que esconde o inconveniente.** A B33 recusou filtro por ação na
  trilha por isso.
- **A promessa que o software não cumpre.** Já aconteceu quatro vezes. Toda tela
  pública se confere contra o comportamento real, e o conserto não é a frase: é
  a varredura.
- **O default que decide por ela.** Onde o produto decide calado, é achado —
  mesmo quando o default é bom.
- **O campo que não faz o que ela digitou.** Achado em 02/09: dinheiro com dois
  parsers incompatíveis e checkbox que não desliga. Ver B48.

---

## 10 · Severidade, quando você achar algo de passagem

| | o que significa |
|---|---|
| **S1 · bloqueia** | ela não conclui a tarefa, desiste, ou **conclui errado sem saber** |
| **S2 · custa confiança** | erro provável numa decisão de dinheiro ou de paciente; retrabalho; promessa de tela que o software não cumpre |
| **S3 · atrito** | ela consegue, com toque, dúvida ou volta desnecessária |
| **S4 · ruído** | inconsistência de nome, hierarquia, espaçamento |

Só **S1 e S2** abrem build nova. S3 e S4 entram como linha na build-vassoura
(**B47**). Achado sem prova — rota + arquivo + linha, ou nome de função no banco
com o trecho do corpo, ou consulta SQL rodada com o resultado — não é achado, é
palpite.

---

## 11 · A conta de demonstração

Existe `demo@sessoes.com.br`, com 8 pacientes fictícios e 5 cobranças.
**Nunca use a conta real do Leandro** — ela tem pessoa de verdade dentro.

Atenção: a conta demo tem **zero `janelas_atendimento`**, então o cockpit dela
mostra três travessões. Isso é o comportamento correto (nulo, não zero), e é
também o motivo de ela ser um mau cartão de visitas — ver B47.
