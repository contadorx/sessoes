# B31 · Plano terapêutico leve e encerramento guiado

**2,5 dias (era 2; +0,5 pelo S2 da auditoria) · migração: a definir · nona da fila**
**Códigos:** PR9, PR14.

---

## Entrega

**1 · Plano terapêutico leve.** Objetivos com data de revisão. Leve significa
leve: não é plano de tratamento estruturado, é o que ela já anota.

**2 · Encerramento guiado** (alta / abandono / encaminhamento) que **exige o
registro de encerramento antes de arquivar** — é conteúdo mínimo do CFP (bloco 4
da Res. 001/2009 e do Manual de nov/2025), não campo opcional.

Amarra com a vaga fixa da B22: alta encerra o combinado e o horário vai para a
fila de entrada.

**3 · O S2 da auditoria: o painel da sessão respeita a permissão.**

```
components/app/PainelSessao.tsx:337-345   não recebe `acessos`
components/app/PainelSessao.tsx:434-446   <Evolucao camada="prontuario" comecaAberta />
components/app/PainelSessao.tsx:420       <Recebi />

banco: policy "evolucoes da conta: criar"  → exige le_clinico()
banco: policy "cobranças da conta: criar"  → exige ve_financeiro()
```

O painel é o mesmo para todo mundo que abre a agenda. Uma **secretária** (padrão:
sem clínico, sem financeiro) marca "Aconteceu" e recebe, ali mesmo, uma caixa de
evolução já aberta, com *"Guarda de cinco anos: o que entra aqui não se apaga"*
embaixo, e o bloco "Recebi". **A RLS recusa os dois.** As abas do paciente estão
certas (`SemAcessoClinico` em `prontuario/page.tsx:23` e `anamnese/page.tsx:22`);
o painel da agenda ficou de fora.

`lib/permissao.ts` existe para isso e diz a frase: *"oferecer e depois recusar é
pior do que não oferecer"*. Aqui é pior que oferecer: é convidar quem não pode
ler prontuário a escrever num.

Conserto: passar `acessos` até o painel; `<Evolucao>` dentro de `podeClinico`,
`<Recebi>` dentro de `podeFinanceiro`.

**4 · Arquivar diz, antes, o que vai acontecer.** `components/app/Privacidade.tsx:171-176`
diz só "a ficha vira só leitura" e pede o texto de encerramento. O que
`arquivar_paciente` **também** faz e a tela não menciona: encerra o combinado
vigente, apaga a pessoa de `fila_encaixe` e `fila_entrada`, cancela as mensagens
pendentes — e o encerramento dispara `ao_encerrar_enquadre`, que **abre uma
`vaga_fixa` com motivo `alta`**. A terça das 15h entra na fila de entrada, e ela
não foi avisada.

---

## Pronto quando

- [ ] **arquivar sem registro de encerramento é impossível pelo banco** (hoje
      `arquivar_paciente` já exige o texto; o que falta é ele ser o bloco 4 do
      registro, e não uma anotação solta);
- [ ] **nenhuma tela oferece escrita clínica a quem a RLS vai recusar**,
      verificado **entrando com o papel `secretaria`** — não lendo o código;
- [ ] o texto de confirmação do arquivamento nomeia o horário que vai ser
      oferecido;
- [ ] um objetivo com data de revisão vencida aparece onde ela olha, sem virar
      alerta sobre a paciente.

---

## Não entra

- **Sugestão de conduta, de frequência ou de meta clínica.** Fronteira 3, e o D8
  morreu por isso. O plano é o que **ela** escreveu; o produto guarda e devolve.
- **Esconder o botão "Aconteceu" da secretária.** Marcar realizada é fato
  administrativo e é o que ela existe para fazer — tirar isso devolve o trabalho
  para a psicóloga, que é o oposto do produto inteiro.
- **Apagar ao arquivar.** Encerrar nunca é apagar: o prontuário arquiva imutável
  pelo prazo de guarda.

---

## Arquivos que esta build toca

```
components/app/PainelSessao.tsx   components/app/Semana.tsx  (passar `acessos`)
components/app/Privacidade.tsx    components/app/Registro.tsx
lib/permissao.ts (só leitura)
app/(app)/pacientes/acoes.ts
supabase/migrations/  (plano terapêutico, bloco 4 do registro)
```

**Suítes a rodar depois:** `0036_vaga_fixa.sql` · `0049` (permissões) ·
`0045` (a que reprova função do painel que mencione tabela clínica) · a suíte do
registro clínico.
