create table visit (
  id bigserial primary key,
  name varchar(100) not null,
  visited_at timestamp not null default current_timestamp
);
