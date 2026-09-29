## List of URLs with JNLP files that can be used for testing (_not all of them work, some are very outdated_)

- https://docs.oracle.com/javase/tutorialJWS/samples/uiswing/ButtonDemoProject/ButtonDemo.jnlp (**status** Works)
- https://www.sweethome3d.com/SweetHome3D.jnlp (**status** Doesn't work)
- https://www.jgoodies.com/download/jdiskreport/jdiskreport.jnlp (**status** Works)
- https://www.jgoodies.com/download/demos/showcase/smart-client-showcase.jnlp (**status** Works)
- https://www.jgoodies.com/download/demos/skeleton/skeleton.jnlp (**status** Works)
- https://www.jgoodies.com/download/demos/looks/looksdemo.jnlp (**status** Works)
- https://www.jgoodies.com/download/demos/metamorphosis/metamorphosis.jnlp (**status** Works)
- https://aladin.cds.unistra.fr/java/aladin.jnlp (**status** Works)
- https://sscweb.gsfc.nasa.gov/tipsod/tipsod-all.jnlp (**status** Doesn't work)
- https://das2.org/autoplot/latest/autoplot.jnlp (**status** Works)

### Example
```PowerShell
Start-Process -FilePath "C:\Program Files\IcedTeaWeb\WebStart\bin\javaws.exe" -ArgumentList "-verbose https://aladin.cds.unistra.fr/java/aladin.jnlp" -NoNewWindow -Wait
```
