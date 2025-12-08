<b>Encerra o PDV e mata a interface</b>
```
pkill -9 pdvJava2 ; pkill -9 jav ; pkill -9 lnx ; sleep 3 ; pkill -9 chro
```

<b>Força atualização das LIBs do TEF</b>
```
cd /Zanthus/Zeus/pdvJava && wget -q "http://serv-web/uploads/interfaceZanthus/libCliSiTef.7z" -O "/Zanthus/Zeus/pdvJava/libCliSiTef.7z" && 7z x -o/Zanthus/Zeus/pdvJava/ -y libCliSiTef.7z && reboot
```

<b>Atualiza arquivos de comunicação</b>
```
nano CARG*  RESTG*  ZMWS*
```

<b>Apaga arquivos NVL USE COM CAUTELA! Isso apaga os arquivos de venda do PDV</b>
```
mkdir -p BKUPNVL && mv -f *.NVL BKUPNVL/
```
<b>Rollback de versão MóduloPHP Caixas</b>
```
cd /Zanthus/Zeus/pdvJava/GERAL/SINCRO/WEB/ ; mkdir -p crash ; mv moduloPHPPDV crash ; cp -a moduloPHPPDV_OLD moduloPHPPDV
```
<b>Copia Versão PHP PDV de um terminal ao lado</b>
```
rsync -avz --delete root@192.168.8.121:/Zanthus/Zeus/pdvJava/GERAL/SINCRO/WEB/moduloPHPPDV/ /Zanthus/Zeus/pdvJava/GERAL/SINCRO/WEB/moduloPHPPDV/
```
