from example.i18n import define_message


GREETING = define_message(
    id="python.greeting",
    default_message="Hello, {name}!",
    description="Greeting from Python",
)
