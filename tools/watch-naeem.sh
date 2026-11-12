#!/bin/bash
# Watch Naeem Malik's (GitHub malik-na) S2R work: the heads of his branches, with the newest commit subject.
# State in ~/.local/state/deepidle/naeem-heads; a changed head prints NEW and sends an agent-notify. Read only.
S=~/.local/state/deepidle; mkdir -p $S; F=$S/naeem-heads; touch $F; new=0
for spec in malik-na/linux-aurora:m1power/s2r-mem malik-na/linux-aurora:m1power/s2r-pmp malik-na/linux-aurora:m1power/s2r-rs1 malik-na/m1-power-lab:omarchy-live-power; do
    repo=${spec%%:*}; br=${spec#*:}
    j=$(gh api "repos/$repo/commits/$(printf %s "$br" | sed 's|/|%2F|g')" --jq '[.sha[0:10],.commit.author.date,(.commit.message|split("\n")[0])]|@tsv' 2>/dev/null) || continue
    sha=${j%%$'\t'*}; old=$(grep "^$spec " $F | cut -d' ' -f2)
    if [ "$sha" != "$old" ]; then
        echo "NEW $spec: $j"; new=1
        grep -v "^$spec " $F > $F.tmp; echo "$spec $sha" >> $F.tmp; mv $F.tmp $F
        [ -n "$old" ] && agent-notify send -m "Naeem pushed to $spec: ${j#*$'\t'}" >/dev/null
    else echo "same $spec $sha"; fi
done
# any new branch on his linux-aurora fork
gh api repos/malik-na/linux-aurora/branches --jq '.[].name' 2>/dev/null | tr '\n' ' '; echo
exit 0
