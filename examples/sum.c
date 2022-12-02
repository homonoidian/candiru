#include <stdlib.h>
#include <stdio.h>

typedef struct point_t
{
  double x;
  double y;
} Point;

typedef struct rect_t
{
  Point *origin;
  Point *extent;
} Rect;

typedef struct rect_list_t RectList;

struct rect_list_t
{
  Rect *rect;
  RectList *next;
};

Point *Point_New(double x, double y)
{
  Point *point = malloc(sizeof(Point));
  point->x = x;
  point->y = y;
  return point;
}

void Point_Free(Point *point)
{
  free(point);
}

Point *Point_Add(Point *a, Point *b)
{
  return Point_New(a->x + b->x, a->y + b->y);
}

Point *Point_Sub(Point *a, Point *b)
{
  return Point_New(a->x - b->x, a->y - b->y);
}

Point *Point_Mul(Point *a, Point *b)
{
  return Point_New(a->x * b->x, a->y * b->y);
}

Point *Point_Div(Point *a, Point *b)
{
  return Point_New(a->x / b->x, a->y / b->y);
}

void Point_See(Point *point)
{
  printf("%f @ %f\n", point->x, point->y);
}

void Rect_See(Rect *rect)
{
  printf("%f @ %f x %f @ %f\n", rect->origin->x, rect->origin->y, rect->extent->x, rect->extent->y);
}

Rect *Rect_New(Point *origin, Point *extent)
{
  Rect *rect = malloc(sizeof(Rect));
  rect->origin = origin;
  rect->extent = extent;
  return rect;
}

void Rect_Free(Rect *rect)
{
  Point_Free(rect->origin);
  Point_Free(rect->extent);
  free(rect);
}

RectList *RectList_New()
{
  RectList *list = malloc(sizeof(RectList));
  list->rect = NULL;
  list->next = NULL;
  return list;
}

void RectList_Append(RectList *head, Rect *rect)
{
  if (head->rect == NULL)
  {
    head->rect = rect;
    return;
  }

  RectList *tmp = RectList_New();
  tmp->rect = rect;

  RectList *p = head;
  while (p->next != NULL)
  {
    p = p->next;
  }

  p->next = tmp;
}

void RectList_Free(RectList *head)
{
  if (head == NULL)
    return;

  Rect_Free(head->rect);
  RectList_Free(head->next);
  free(head);
}
