###### setup crew ai
```


py -3.12 -m venv .venv
crewai create crew demo_ai_topressearchers
// input role, goal, desc ... etc

Add-Content .gitignore ".env"
Add-Content .gitignore ".venv"
 .\.venv\Scripts\activate

   uv add "crewai[anthropic]"
   uv add 'crewai[litellm]'
   uv add "crewai[tools]" --upgrade; uv add litellm --upgrade

   pip install -U litellm crewai

```