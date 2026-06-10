## Do
- Write all the code and variable names in english, even if you receive instructions in a different language
- Upon each change:
    - Update the Structure.md file to reflect the current state of the project
    - Update the firestore.rules and firestore.indexes if needed
    - Update the widget_catalog.md file to reflect the current state of the project
    - Update the test folder if needed
    - Update storage.rules if needed
    - Update cloud functions documentation if needed
    - Update the .gitignore file if needed
    - Check for a conflict with the database_schema.md file, if there is a conflict, plan a refactor strategy

- Always add spanish translations for the UI text
- Keep the comments in the code updated and concise
- Keep the README.md updated
- Refer to Structure.md to gather information about the project

## Don't
- Hardcode strings, always use the l18n system
- Use 'value' in DropdownButtonFormField since it is deprecated. Use initialValue instead.
- Use print(). Always use debugPrint() for console logs.
- Use primaryColor.withOpacity(), use Theme.of(context).colorScheme.withValues() for the UI

