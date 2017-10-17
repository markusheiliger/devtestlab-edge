# SonarQube - Linux

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fmarkusheiliger%2Fdevtestlab-edge%2Fmaster%2Fenvironments%2FSonarQube-Linux%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>

SonarQube (formerly known as Sonar) is an open source tool suite to measure and analyse to quality of source code. It is written in Java but is able to analyse code in about 20 different programming languages.

**Notice** - Once deployed SonarQube can take a while to start due the creation of the initial empty database, it can even fail if you try to access it directly, allow to start it before accessing it or even adjust the tier for the webapp and / or database accordingly.